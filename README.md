Hello, NL JUG!👋

I'm very excited about this opportunity to talk with you in writing about GraalVM, Spring Boot, how they are even more awesome together, and why you should care. Let's go!

# What is GraalVM and why GraalVM

GraalVM is a JDK, just like OpenJDK or any other JDK of your choice, but with additional features and capabilities built on top of it. Let's explore them.

One such feature is the **GraalVM JIT compiler**. It's a brand new highly optimizing compiler, which is the outcome of over a decade of research at Oracle Labs.By moving to GraalVM JIT (by just setting GraalVM as your Java runtime), you ca n easily win extra 10-15% performance improvements. Not every application is performance-critical, but for those that are, every percent of performance improvement, especially with easy migration and no manual tuning required, is a huge win. This is confirmed by both large-scale organization, such as Oracle NetSuite, using GraalVM JIT in production at scale, and community reports, such the one from Ionut Balosin and Florin Blanaru (https://ionutbalosin.com/2024/02/jvm-performance-comparison-for-jdk-21/), where Oracle GraalVM JIT shows performance improvement of 23% on x86_64 and 17% on arm64 compared to the C2 JIT compiler. Another great example that showed the true power of GraalVM compiler was the 1 Billion Rows Challenge. There are many conclusions and observations that we made during this challenge, but I would like to quote one specific observation from Jaromir Hamala from QuestDB: even if you have heavily hand-optimized code, such as what participants wrote for 1BRC, a good compiler can still surprise you and help you squeeze those few extra performance bits.

Another feature that GraalVM adds to the JDK is **Embedding other languages**. We are lucky to have the incredibly rich Java ecosystem at our fingertips – whenever we have a problem that needs a solving, there's always a Java library or tool for that. But sometimes we need to reach out for one specific library on another ecosystem, such as all the cool and shiny ML libraries in Python, or utilize the scripting capabilities of JavaScript. GraalVM, and more specifically its Truffle component, enables you doing just that: embedding what we call guest language code in your Java application. You use what you need to use, and we will take care of the rest: interoperability, performance, tooling, and security. This way you can combine the rich and powerful Java platform with any other library or tool that you like – how cool is that? In terms of use cases, I mentioned embedding Python libraries, where we see a lot of interest from the community, and along with that there are other scenarios, where embeddability is very useful. One such case is NetSuite,  which uses GraalVM's JavaScript runtime to execute user scripts on their platform. With GraalVM, you can extend your Java application with any of the implemented languages, or even write your own implementation in Java.

Now the last but not least is GraalVM's **Native Image**, which enables compiling Java applications ahead of time into small and fast native executables. This our main topic for today — let's dive in.

# Meet GraalVM Native Image

so what is Native Image and how does it work exactly? Native Image is a feature in GraalVM that employs the Graal compiler to ahead of time compile your Java application into a native executable. The main reason to do so is to shift all the work that the JVM normally does at run time, such as loading classes, profiling, and compilation, to the build time, to remove that overhead when you run your application. In addition to AOT compilation, Native Image performs another important task: it takes a snapshot of your heap with objects that are safe to initialize at build time, to reduce the allocation overhead as well. As the artifact it produces a native executable with the following advantages:

* Fast startup and instant performance, as the native executable doesn't need to warm up;
* Low memory footprint, as we don't need to profile and compile code at runtime;
* Peak performance on par with the JVM;
* Compact packaging;
* Additional security, as we eliminate unused code and reduce the attack surface.

 # Spring AOT: Spring meets GraalVM 🤝

By default Spring Boot works in a way that at runtime it pulls your projects source code and configuration from all the different sources, resolves it, and and creates an internal representation of your app. What's interesting, GraalVM Native Image does a very similar thing – analyzes incoming code and configuration and creates an internal representation of your app – but it does so at build time. The Spring AOT engine was designed to bridge this gap between two worlds. It transforms your application configuration into native-friendly functional configuration and generates additional files to assist native compilation of Spring projects: 

* Java source code (functional configuration)
* Bytecode for things like dynamic proxies
* Runtime hints for dynamic Java features when necessary (reflection, resources, etc). 


# Build a Native Spring Application

Let's go to Josh Long's second favorite place — start.spring.io – and generate our project. The settings I chose are Spring Boot 3.3.1, Java 22, Maven, and my dependencies are Spring Web and GraalVM Native Image. That's all. Let's download and unpack our project, and add a `HelloController.java` so we have something to work with:

```java
package com.example.demo;

import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.GetMapping;

@RestController
public class HelloController {

    @GetMapping("/hello")
    public String hello() {
        return "Hello from GraalVM and Spring!💃";
    }
    
}
```
Guess what — we would also need GraalVM. The easiest way to install it with SDKMAN!. As I'm writing this article the latest released version is GraalVM for JDK 22, but we can also be cool and get the early access builds of GraalVM for JDK 23:

```shell
sdk install java 23.ea.9-graal

```

Now we are all set!

Remember GraalVM is a normal JDK, right? You can run your application as you would on any other JDK:

```shell
mvn spring-boot:run
...
Tomcat started on port 8080 (http) with context path '/'
Started DemoApplication in 1.106 seconds (process running for 1.363)
```

Navigate to `http://localhost:8080/hello` and you'll see our message. 

So far so good, but where's fun in that! Let's compile it to native executable with GraalVM Native Image:

```mvn -Pnative native:compile```

While this command looks simple on the surface, it invokes an elaborate process of analyzing your whole applications, pulling the configuration, finding the code that is reachable, snapshotting heap, and then optimizing and compiling. Look at the analysis step — even our fairly trivial app with two user classes (albeit also dependencies on Spring modules and JDK classes), has quite a few things inside:

```shell
[2/8] Performing analysis...  [*****]                                   (15.0s @ 1.53GB)
   16,960 reachable types   (89.4% of   18,971 total)
   26,038 reachable fields  (59.2% of   44,015 total)
   89,842 reachable methods (64.9% of  138,456 total)
```

On my pretty average Linux cloud instance (16 COU, 32 GB RAM) the build takes 1m 15s by default, and 46.7s with the quick build mode (`-Ob`). 

We can also quickly assess the runtime characteristics of our application. The size of our application is 62MB, and measuring the runtime memory usage (RSS) without any tweaking and serving incoming requests load gives us 69 MB. Not bad, right?

But let's do performance benchmarking, and for that let's talk performance.

# Optimize performance

You might say: ok, I can see how compiling things AOT is great for startup, memory usage, packaging size, but what about peak performance and famous JVM profiling and dynamic code execution? Indeed, we all know that the JVM profiles our application and adapts on the go to better invest optimization efforts into the parts of the application that are most frequently executed. And we said about Native Image compilation that runtime hasn't happened yet, so how can you reach high peak performance? I'm glad you asked! Let's talk about profile-guided optimizations.

## PGO 🚀

One of the most powerful performance optimizations in Native Image is profile-guided optimizations (PGO). You can build an instrumented version of your application, do a "training run" applying relevant workloads, and this will generate a profiles file that will be automatically picked up by Native Image to guide optimizations. This way you can combine the best of both worlds: the runtime awareness of the JVM, and the powerful AOT optimizations of Native Image. Your application performance wil depend on the quality of profiles, but with good profiles it's possible to reach peak performance on par with the JVM.


Let's build a PGO-optimized image. To follow along, you might to want to clone the related repo, as it comes with profiles and benchmarking scripts: https://github.com/alina-yur/nljug-native-spring-boot.

1. Build an instrumented image: 

```mvn -Pnative,instrumented native:compile```

2. Run the app and apply relevant workload:

```./target/demo-instrumented```

```hey -n=1000000 http://localhost:8080/hello```

after you shut down the app, you'll see an `iprof` file in your working directory.

3. Build an app with profiles (they are being picked up via `<buildArg>--pgo=${project.basedir}/default.iprof</buildArg>`):

```mvn -Pnative,optimized native:compile```

This will give you `demo-optimized`, that is aware of the application behavior at runtime and has a better performance.

Let's look at other performance optimizations available in GraalVM Native Image, and then do performance benchmarking.


## ML-enabled PGO 👩‍🔬

The PGO approach described above, where the profiles are collected during a training run and tailored to your app, is the recommended way to do PGO in Native Image. 

There can be situations though when collecting profiles is not possible – for example, because of your deployment process. In that case, it's still possible to get profiling information and optimize the app based on it via machine learning enabled PGO. Native Image contains a pre-trained ML model that predicts the probabilities of the control flow graph branches, which lets us additionally optimize the app. This is again available in Oracle GraalVM and you don't need to enable it – it kicks in automatically  in the absence of user-provided profiles. 

If you are curious about the impact if this optimization, you can disable it with `-H:-MLProfileInference`. In our measurements, this optimization provides ~6% runtime performance improvement, which is pretty cool for an optimization you automatically get out of the box.


## G1 GC 🧹

There could be different GC strategies. The default GC in Native Image, Serial GC, can be beneficial in certain scenarios, for example if you have a short-lived application or want to optimize memory usage. 

If you are aiming for the best peak throughput, our general recommendation is to try the G1 GC (Note that you need Oracle GraalVM for it). 

In our `optimized` profile it's enabled via `<buildArg>--gc=G1</buildArg>`.

## Optimization levels in Native Image

There are several levels of optimizations in Native Image, that can be set at build time for different purposes:

- `-O0` - No optimizations: Recommended optimization level for debugging native images;

- `-O1` - Basic optimizations: Basic GraalVM compiler optimizations, still works for debugging;
 
- `-O2`  - Advanced optimizations: default optimization level for Native Image;

- `-O3` - All optimizations for best performance;

- `-Ob` - Optimize for fastest build time: use only for dev purposes for faster feedback, remove before compiling for deployment;

- `-pgo`: Using PGO will automatically trigger `-O3` for best performance.


## `march=native`


 If you are deploying your application on the same machine where you building it, or a similar machine with support for the same CPU features, use `-march=native` for additional performance. This option allows the Graal compiler to use all CPU features available, which will improve the performance of your application. Note that if you are building your application to distribute it to your users or customers, where the machine configuration is unknown, it's better to use `-march=compatibility`.


## Performance comparison

Let's run our application on the JVM and Native Image, and compare the results. To benchmark the peak throughput, we will send 2 batches of 250000 requests (warmup run and benchmarking run) using hey


JVM
Warmup runs: 27606 - 48764 requests/sec
Benchmarking run: 51822 requests/sec
Maximum resident set size: 469.12 MB

Native Image

Warmup run: 50167.0774 requests/sec
Benchmarking run: 49779.2698 requests/sec
Maximum resident set size: 412.3 MB


# Testing 🧪

GraalVM's Native Build Tools support testing applications as native images, including JUnit support. The way this works is that your tests are compiled as native executables to verify that things work in the native world as expected. Test our application with the following:

 ```mvn -PnativeTest test```

In our example, `HttpRequestTest` will verify that the application returns the expected message.

Native testing recommendation: you don't need to test in the mode all the time, especially if you are working with frameworks and libraries that support Native Image – usually everything just works. Develop and test your application on the JVM, and test in Native once in a while, as a part of your CI/CD process, or if you are introducing a new dependency, or changing things that are sensitive for Native Image (reflection etc). 

# Using libraries

But why do we need this extra step? Native Image compiles applications ahead of time, meaning that runtime hasn't happened yet. Since we need a complete picture of the app, compilation happens under a closed-world assumption: everything there is to know about your app, **needs to be known at build time**. Native Image's static analysis will try to make the best possible predictions about the runtime behavior of your application, but for those cases where it's not sufficient, you might need to provide configuration files to make things like reflection, resources, JNI, serialization, and proxies "visible" to Native Image. Note the word "configuration" doesn't mean that this is something that you need to do manually – let's look at all the many ways how this can just work.

When using libraries in native mode, some things such as reflection, resources, proxies might have to be made "visible" to Native Image at build time via configuration. Now the word "configuration" doesn't mean that this is something that you need to do manually as a user – let's look at all the many ways how this can just work.

* Ideally, a library would include the necessary config files. Example: [H2](https://github.com/h2database/h2database/blob/master/h2/src/main/META-INF/native-image/reflect-config.json), [OCI Java SDK](https://github.com/oracle/oci-java-sdk/blob/master/bmc-adm/src/main/resources/META-INF/native-image/com.oracle.oci.sdk/oci-java-sdk-adm/reflect-config.json). In this case no further action needed from a user – things just work.
* In cases when a library doesn't (yet) support GraalVM, the next best option is having configuration for it in the [GraalVM Reachability Metadata Repository](https://github.com/oracle/graalvm-reachability-metadata). It's a centralized repository where both maintainers and users can contribute and then reuse configuration for Native Image. It's integrated into [Native Build Tools](https://github.com/graalvm/native-build-tools) and now enabled by default, so as a user, again things just work.<br>
For both of those options, a quick way to asses whether your dependencies work with Native Image is the ["Ready for Native Image"](https://www.graalvm.org/native-image/libraries-and-frameworks/) page. Note that this is a list of libraries that are *known* to be continuously testing with Native Image, and there are more compatible libraries out there; but this is a good first step for assessment. 
* You can use framework support to produce custom “hints” for Native Image:
```java
runtimeHints.resources().registerPattern(“config/app.properties”); //register a resource
```

* You can use the Tracing Agent to produce the necessary config [automatically](https://www.graalvm.org/latest/reference-manual/native-image/metadata/AutomaticMetadataCollection/).
* You can provide/extend config for reflection, JNI, resources, serialization, and predefined classes [manually in JSON](graalvm.org/latest/reference-manual/native-image/metadata/#specifying-metadata-with-json).


# Monitoring 📈

Build an application with monitoring features enabled:

```shell
mvn -Pmonitored native:compile
```
This will trigger a profile with the following `buildArgs`: `--enable-monitoring=heapdump,jfr,jvmstat`. You can also opt for using just one of those monitoring features. 

Let's start the app:

```shell
./target/demo-monitored
```

Now in another terminal tab let's start VisualVM (note that you can also `sdk install visualvm`, how cool is this!):

```shell
visualvm
```

And in a yet another terminal tab let's send some load to the app via `hey` (get it [here](https://github.com/rakyll/hey)):

```shell
hey -n=100000 http://localhost:8080/hello
```

You'll see that our application successfully operates and uses minimal resources even under load. 

You can go even further and repeat the experiment but limiting the memory to let's say ridiculous 10 MB and the app will remain operational:

```shell
./target/demo-monitored -Xmx10M
hey -n=100000 http://localhost:8080/hello
```

# What's next for GraalVM

## Native Image Layers

We want to introduce a brand new way of building and deploying Native Image applications. With Layers you'll be able to create native images that depend on one or more base images. Such application images are much faster to build compared with standalone images, providing an improved development experience. Moreover, base images can be shared not just across applications but potentially also across different operating system processes, which can reduce the overall memory footprint.

GraalOS