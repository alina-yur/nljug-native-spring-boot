set -e

function print() {
    printf "\033[1;34m$1\033[0m\n"
}

print "Starting the app 🏎️"

java -XX:-UseJVMCICompiler -Xmx512m -jar ./target/demo-0.0.1-SNAPSHOT.jar &

export PID=$!

sleep 2
print "Done waiting for startup..."

print "Executing warmup load"
hey -n=250000 -c=8 http://localhost:8080/hello

print "Executing benchmark load"
hey -n=250000 -c=8 http://localhost:8080/hello

print "JVM run is done!🎉"

kill $PID
sleep 1