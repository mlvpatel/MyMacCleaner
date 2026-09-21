import Darwin

func terminateSystemWorkload(_ processIdentifier: pid_t) {
    _ = kill(processIdentifier, SIGTERM)
}
