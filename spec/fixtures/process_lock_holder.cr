path = ARGV[0]
ready = ARGV[1]

file = File.open(path, "a+")
file.flock_exclusive
File.write(ready, "ready")
sleep 3.seconds
file.flock_unlock
file.close
