# FreeBSDKit

A framework for building secure, capability-aware applications on FreeBSD.

FreeBSDKit provides idiomatic Swift, C and C++ interfaces to FreeBSD's unique system features including Capsicum sandboxing, jails, process descriptors, kqueue-based signal handling, and inter-process communication with descriptor passing. The framework embraces move-only semantics (`~Copyable`) to model resource ownership explicitly in the type system.

## Requirements

- FreeBSD 13.0 or later
- Swift 6.3 development snapshot or later

## Installation

Add FreeBSDKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SwiftBSD/FreeBSDKit", from: "0.2.6")
]
```

Then add the specific libraries you need to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "Capsicum", package: "FreeBSDKit"),
        .product(name: "Capabilities", package: "FreeBSDKit"),
        .product(name: "Casper", package: "FreeBSDKit"),
        .product(name: "Descriptors", package: "FreeBSDKit"),
        .product(name: "FPC", package: "FreeBSDKit"),
        .product(name: "Jails", package: "FreeBSDKit"),
        .product(name: "Procctl", package: "FreeBSDKit"),
        .product(name: "ACL", package: "FreeBSDKit"),
        .product(name: "Rctl", package: "FreeBSDKit"),
        .product(name: "Cpuset", package: "FreeBSDKit"),
        .product(name: "DTraceCore", package: "FreeBSDKit"),
        .product(name: "DBlocks", package: "FreeBSDKit"),
        .product(name: "Netmap", package: "FreeBSDKit"),
        .product(name: "Audit", package: "FreeBSDKit"),
        .product(name: "AgeSignal", package: "FreeBSDKit"),
        .product(name: "OpenCrypto", package: "FreeBSDKit"),
    ]
)
```

---

## Libraries

### FreeBSDKit (Core)

Foundation protocols and utilities shared across the framework.

```swift
import FreeBSDKit

// Type-safe sysctl access
let hostname: String = try BSDSysctl.getString("kern.hostname")
let boottime: timeval = try BSDSysctl.get("kern.boottime")
let physmem: Int64 = try BSDSysctl.get("hw.physmem")

// Extended attributes
try ExtendedAttributes.set(
    path: "/path/to/file",
    namespace: .user,
    name: "myattr",
    data: "value".data(using: .utf8)!
)

let data = try ExtendedAttributes.get(
    path: "/path/to/file",
    namespace: .user,
    name: "myattr"
)

// Cryptographic random bytes (blocking, from kernel)
let key = try BSDRandom.bytes(32)
let nonce: UInt64 = try BSDRandom.value()

// Fast random (arc4random, never blocks)
let id = Arc4Random.uint32()
let diceRoll = Arc4Random.uniform(6) + 1
let shuffled = Arc4Random.shuffled([1, 2, 3, 4, 5])
```

**Key Types:**
- `BSDSysctl` - Type-safe sysctl reading and writing
- `BSDRandom` - Cryptographic random bytes via getrandom(2)
- `Arc4Random` - Fast CSPRNG via arc4random(3)
- `ExtendedAttributes` - Extended attribute operations on files and descriptors
- `BSDError` - Unified error handling for BSD system calls
- `BSDSignal` - Signal enumeration with catchability checks
- `BSDResource` - Protocol for ownership-aware resources

---

### Capsicum

Swift interface to FreeBSD's Capsicum capability-mode sandbox.

```swift
import Capsicum

// Check if already in capability mode
let inCapMode = try Capsicum.status()

// Enter capability mode (irreversible)
try Capsicum.enter()

// After this point, global namespaces are inaccessible.
// Only operations on existing file descriptors with
// appropriate rights are permitted.
```

**Limiting Descriptor Rights:**

```swift
import Capsicum

// Create a right set with specific capabilities
let rights = CapsicumRightSet(rights: [
    .read,
    .write,
    .fstat,
    .seek
])

// Limit a file descriptor (rights can only be reduced, never expanded)
_ = CapsicumHelper.limit(fd: fd, rights: rights)

// Limit allowed fcntl operations
try CapsicumHelper.limitFcntls(fd: fd, rights: [.getfl, .setfl])

// Limit allowed ioctl commands
try CapsicumHelper.limitIoctls(fd: fd, commands: [
    IoctlCommand(rawValue: FIONREAD)
])
```

**Key Types:**
- `Capsicum` - Enter capability mode and query status
- `CapsicumRightSet` - Set of capability rights for a descriptor
- `CapsicumRight` - Individual capability rights (read, write, seek, etc.)
- `FcntlRights` - Allowed fcntl operations
- `IoctlCommand` - Allowed ioctl commands

---

### Descriptors

Move-only descriptor types with explicit ownership semantics.

```swift
import Descriptors

// All descriptors are ~Copyable (move-only)
// Ownership transfers on assignment, preventing use-after-close

var file = FileCapability(fd)

// Read from a descriptor
let result = try file.read(maxBytes: 4096)
switch result {
case .data(let bytes):
    print("Read \(bytes.count) bytes")
case .eof:
    print("End of file")
}

// Write to a descriptor
let written = try file.writeOnce(data)

// Descriptor is closed when consumed
file.close()
```

**Socket Operations:**

```swift
import Descriptors

// Create a Unix domain socket
var socket = try SocketCapability.create(
    domain: .unix,
    type: .stream,
    protocol: 0
)

// Bind and listen
try socket.bind(path: "/tmp/my.sock")
try socket.listen(backlog: 5)

// Accept connections
var client = try socket.accept()
```

**Pipe Operations:**

```swift
import Descriptors

// Create a pipe pair
let (read, write) = try PipeCapability.create()

// Write to the pipe
try write.writeOnce("Hello".data(using: .utf8)!)

// Read from the pipe
let result = try read.read(maxBytes: 100)
```

**Device Operations:**

```swift
import Descriptors

// Open a device
var device = try DeviceCapability.open(
    path: "/dev/random",
    flags: [.readOnly]
)

// Read random bytes
let result = try device.read(maxBytes: 32)

// Query device properties
let deviceType = try device.deviceType()
let isDisk = try device.isDisk()

// For block devices
let sectorSize = try device.sectorSize()
let mediaSize = try device.mediaSize()
```

**Key Types:**
- `FileCapability` - Regular file descriptor
- `DirectoryCapability` - Directory descriptor with openat support
- `DeviceCapability` - Device file descriptor with ioctl support
- `SocketCapability` - Socket descriptor
- `PipeReadCapability` / `PipeWriteCapability` - Pipe endpoints
- `KqueueCapability` - Kqueue event notification
- `ProcessCapability` - Process descriptor (pdfork)
- `SharedMemoryCapability` - POSIX shared memory
- `EventCapability` - Eventfd-like notifications
- `SystemJailDescriptor` - Jail descriptor

---

### Capabilities

Capsicum capability wrappers for descriptors with built-in right limiting.

```swift
import Capabilities

// Open a file with capability wrapping
var file = FileCapability(fd)

// Limit rights directly on the capability
_ = file.limit(rights: CapsicumRightSet(rights: [.read, .fstat]))

// Limit fcntl/ioctl operations
try file.limitFcntls(rights: [.getfl])
try file.limitIoctls(commands: [])

// Query current limits
let fcntls = try file.getFcntls()
let ioctls = try file.getIoctls()
```

**Directory-Relative Operations (Capsicum-Safe):**

```swift
import Capabilities

// Open a directory capability
var dir = try DirectoryCapability.open(path: "/var/data")

// Open files relative to the directory (works in capability mode)
var file = try dir.openFile(relativePath: "config.json", flags: [.readOnly])

// Create subdirectories
try dir.createDirectory(relativePath: "cache", mode: 0o755)

// Stat files relative to directory
let st = try dir.stat(relativePath: "config.json")
```

---

### SignalDispatchers

Kqueue and libdispatch-based signal handling.

```swift
import SignalDispatchers
import Descriptors

// Create a kqueue for signal delivery
var kq = try KqueueCapability.create()

// Create handler for specific signals
let handler = try KqueueSignalHandler(
    kqueue: kq,
    signals: [.int, .term, .hup]
)

// Register handlers
await handler.on(.int) {
    print("Received SIGINT")
}

await handler.on(.term) {
    print("Received SIGTERM, shutting down...")
}

// Run the signal handling loop (never returns normally)
try await handler.run()
```

**Using libdispatch:**

```swift
import SignalDispatchers

// GCD-based signal handling
let handler = try GCDSignalHandler(signals: [.int, .term])

handler.on(.int) {
    print("SIGINT received")
}

handler.on(.term) {
    print("SIGTERM received")
}

// Signals are delivered via GCD
```

---

### Jails

Interface to FreeBSD jail management.

```swift
import Jails
import Descriptors

// Build jail parameters
var iov = JailIOVector()
iov.add(key: "name", value: "myjail")
iov.add(key: "path", value: "/jail/myjail")
iov.add(key: "host.hostname", value: "jailed.local")
iov.add(key: "persist", value: true)

// Create jail and get descriptor
let flags: JailSetFlags = [.create, .getDesc, .ownDesc]
var jailDesc = try SystemJailDescriptor.set(iov: &iov, flags: flags)

// Attach current process to jail
try jailDesc.attach()

// Remove jail (requires owning descriptor)
try jailDesc.remove()
```

---

### FPC (Free Process Communication)

IPC protocol with descriptor passing over Unix sockets.

```swift
import FPC

// Server side
let listener = try FPCListener(path: "/tmp/myservice.sock")

while true {
    var endpoint = try await listener.accept()

    // Receive a message
    var request = try await endpoint.receive()

    // Extract descriptors from message
    if let file = request.fileDescriptor(at: 0) {
        // Process the received file descriptor
    }

    // Send a reply
    let reply = FPCMessage.reply(to: request, id: .pong)
    try await endpoint.send(reply)
}
```

**Client Side:**

```swift
import FPC

// Connect to server
var endpoint = try await FPCClient.connect(path: "/tmp/myservice.sock")

// Send a request with file descriptors
var fd = FileCapability(openedFd)
let message = FPCMessage.request(
    .lookup,
    payload: "config".data(using: .utf8)!,
    descriptors: [fd.toOpaqueRef()]
)
try await endpoint.send(message)

// Receive reply
let reply = try await endpoint.receive()
```

**Custom Message IDs:**

```swift
extension MessageID {
    // User message IDs start at 256
    static let fileOpen = MessageID(rawValue: 256)
    static let fileOpenReply = MessageID(rawValue: 257)
    static let processSpawn = MessageID(rawValue: 258)
}
```

**Wire Format:**
- 16-byte header with version, message ID, correlation ID, flags
- Up to 64KB inline payload
- Up to 16 file descriptors per message
- Out-of-line (OOL) support for larger payloads via shared memory

---

### MacLabel

Security labeling tool for FreeBSD MAC Framework integration.

```swift
import MacLabel

// Load configuration from JSON
let config = try LabelConfiguration<FileLabel>.load(from: configPath)

// Create labeler
var labeler = Labeler(configuration: config)
labeler.verbose = true

// Validate all paths exist before applying
try labeler.validateConfiguration()

// Apply labels to files
let results = try labeler.apply()

for result in results {
    if result.success {
        print("Labeled: \(result.path)")
    } else {
        print("Failed: \(result.path) - \(result.error!)")
    }
}

// Verify labels match configuration
let verification = try labeler.verify()
```

**Configuration Format (JSON):**

```json
{
    "attributeName": "mac_labels",
    "labels": [
        {
            "path": "/usr/local/bin/myapp",
            "attributes": {
                "security_level": "high",
                "network_access": "restricted"
            }
        },
        {
            "path": "/var/data/*",
            "attributes": {
                "data_class": "sensitive"
            }
        }
    ]
}
```

**CLI Tool (`maclabel`):**

```bash
# Validate configuration
maclabel validate -c config.json

# Apply labels
sudo maclabel apply -c config.json

# Show current labels
maclabel show -c config.json

# Verify labels match configuration
maclabel verify -c config.json

# Remove labels
sudo maclabel remove -c config.json
```

---

### Casper

Swift interface to FreeBSD's Casper (libcasper) services for use in Capsicum sandboxes.

Casper provides privileged services to capability-mode processes that lack direct access to global namespaces. Each service runs in a separate sandboxed process and communicates via Unix domain sockets.

```swift
import Casper
import Capsicum

// Initialize Casper BEFORE entering capability mode (single-threaded context)
let casper = try CasperChannel.create()

// Open services you need
let dns = try CasperDNS(casper: casper)
let sysctl = try CasperSysctl(casper: casper)
let pwd = try CasperPwd(casper: casper)
let grp = try CasperGrp(casper: casper)

// Limit services to minimum required operations
try dns.limitTypes([.nameToAddress])
try dns.limitFamilies([AF_INET, AF_INET6])
try sysctl.limitNames([
    ("kern.hostname", .read),
    ("hw.physmem", .read)
])
try pwd.limitUsers(names: ["root", "www"])
try pwd.limitCommands([.getpwnam, .getpwuid])

// Enter capability mode
try Capsicum.enter()

// Use services within the sandbox
let addresses = try dns.getaddrinfo(hostname: "example.com", port: "443")
let hostname = try sysctl.getString("kern.hostname")
if let user = pwd.getpwnam("www") {
    print("www uid: \(user.uid)")
}
```

**Available Services:**

| Service | Purpose | Key Operations |
|---------|---------|----------------|
| `CasperDNS` | DNS resolution | `getaddrinfo`, `getnameinfo`, `gethostbyname` |
| `CasperSysctl` | Sysctl access | `get`, `set`, `getString`, `nameToMIB` |
| `CasperPwd` | Password database | `getpwnam`, `getpwuid`, `getpwent` |
| `CasperGrp` | Group database | `getgrnam`, `getgrgid`, `getgrent` |
| `CasperSyslog` | System logging | `openlog`, `syslog`, `closelog` |

**Syslog Service:**

```swift
import Casper

let casper = try CasperChannel.create()
let syslog = try CasperSyslog(casper: casper)

// Open connection to syslog
syslog.openlog(ident: "myapp", options: [.pid, .cons], facility: .daemon)

// Log messages within capability mode
syslog.syslog(priority: .info, message: "Application started")
syslog.syslog(priority: .err, message: "Something went wrong")

// Close when done
syslog.closelog()
```

---

### Procctl

Swift interface to FreeBSD's `procctl(2)` system call for process control operations.

```swift
import Procctl

// ASLR (Address Space Layout Randomization)
let aslrStatus = try Procctl.ASLR.getStatus()
if aslrStatus.isActive {
    print("ASLR is active")
}
try Procctl.ASLR.forceEnable()  // Takes effect on next exec

// Process tracing control
if try Procctl.Trace.isEnabled() {
    try Procctl.Trace.disable()  // Prevent debugging/tracing
}

// Parent death signal (like Linux PR_SET_PDEATHSIG)
try Procctl.ParentDeathSignal.set(signal: SIGTERM)

// No new privileges (prevent setuid escalation)
try Procctl.NoNewPrivileges.enable()

// Capability trap (SIGTRAP on Capsicum violations for debugging)
try Procctl.CapabilityTrap.enable()
```

**Process Reaper (Container/Supervisor Support):**

```swift
import Procctl

// Become a process reaper - orphaned descendants reparent here instead of init
try Procctl.Reaper.acquire()

// Check reaper status
let status = try Procctl.Reaper.getStatus()
print("Children: \(status.childCount), Descendants: \(status.descendantCount)")

// Get PIDs of all descendants
let pids = try Procctl.Reaper.getPids()
for pid in pids {
    print("PID \(pid.pid), zombie: \(pid.isZombie)")
}

// Kill all descendants
let result = try Procctl.Reaper.killAll(signal: SIGTERM)
print("Killed \(result.killed) processes")

// Release reaper role
try Procctl.Reaper.release()
```

**Security Controls:**

```swift
import Procctl

// W^X (Write XOR Execute) enforcement
let wxStatus = try Procctl.WXMap.getStatus()
if !wxStatus.isEnforced {
    try Procctl.WXMap.enforce()  // Prevent simultaneous W+X mappings
}

// PROT_MAX control (limit mprotect upgrades)
try Procctl.ProtMax.forceEnable()

// Stack gap randomization
try Procctl.StackGap.enable()

// OOM killer protection
try Procctl.OOMProtection.protect(options: .inherit)

// Signal exit logging
try Procctl.LogSigExit.forceEnable()
```

**x86_64-Specific Controls:**

```swift
#if arch(x86_64)
import Procctl

// KPTI (Kernel Page Table Isolation) - Meltdown mitigation
let kptiStatus = try Procctl.KPTI.getStatus()
try Procctl.KPTI.enableOnExec()

// Linear address width (LA48 vs LA57)
let laStatus = try Procctl.LinearAddress.getStatus()
if laStatus.isLA57 {
    try Procctl.LinearAddress.setLA48OnExec()  // Use 48-bit addresses
}
#endif
```

**Available Controls:**

| Control | Purpose |
|---------|---------|
| `ASLR` | Address space layout randomization |
| `Trace` | Process tracing/debugging control |
| `ProtMax` | Implicit PROT_MAX for mprotect |
| `StackGap` | Stack gap randomization |
| `NoNewPrivileges` | Prevent privilege escalation via setuid |
| `CapabilityTrap` | SIGTRAP on Capsicum violations |
| `ParentDeathSignal` | Signal on parent termination |
| `WXMap` | W^X mapping enforcement |
| `LogSigExit` | Signal exit logging |
| `Reaper` | Process reaper for orphan adoption |
| `OOMProtection` | OOM killer protection |
| `KPTI` | Kernel page table isolation (x86_64) |
| `LinearAddress` | Linear address width (x86_64) |

---

### ACL

Swift interface to FreeBSD's POSIX.1e and NFSv4 Access Control Lists.

ACLs provide fine-grained access control beyond traditional Unix permissions, allowing you to grant specific permissions to individual users and groups.

```swift
import ACL

// Get ACL from a file
let acl = try ACL.get(path: "/path/to/file")
print("Brand: \(acl.brand)")  // .posix or .nfs4

// Check if file has extended ACL
if ACL.hasExtendedACL(path: "/path/to/file") {
    print("File has extended ACL entries")
}

// Iterate over entries
acl.forEachEntry { entry in
    print("Tag: \(entry.tag), Permissions: \(entry.permissions)")
}

// Create ACL from Unix mode
if let acl = ACL.fromMode(0o755) {
    try acl.set(path: "/path/to/file")
}

// Parse ACL from text
if let acl = ACL.fromText("user::rwx,group::r-x,other::r-x") {
    print(acl.text ?? "")
}
```

**Builder API for POSIX.1e ACLs:**

```swift
import ACL

// Build a POSIX.1e ACL programmatically
var builder = ACL.builder()
_ = builder.ownerPermissions(.all)                    // rwx for owner
_ = builder.userPermissions(1000, .readWrite)         // rw- for uid 1000
_ = builder.groupPermissions(.readExecute)            // r-x for owning group
_ = builder.groupPermissions(100, [.read])            // r-- for gid 100
_ = builder.otherPermissions([.read])                 // r-- for others

let acl = try builder.build()
try acl.set(path: "/path/to/file")
```

**NFSv4 ACLs with Allow/Deny:**

```swift
import ACL

// Build an NFSv4 ACL with allow/deny entries
var builder = ACL.nfs4Builder()
_ = builder.allowOwner(.fullSet)
_ = builder.denyUser(1000, [.writeData, .delete])
_ = builder.allowGroup(.readSet, flags: [.fileInherit, .directoryInherit])
_ = builder.allowEveryone([.readData, .readACL])

let acl = try builder.build()
try acl.set(path: "/path/to/file", type: .nfs4)
```

**Working with Entries:**

```swift
import ACL

var acl = try ACL()

// Create and configure an entry
let entry = try acl.createEntry()
try entry.setTag(.user)
try entry.setQualifier(1000)  // uid
try entry.setPermissions([.read, .write])

// For NFSv4 ACLs
try entry.setEntryType(.allow)
try entry.setNFS4Permissions([.readData, .writeData, .execute])
try entry.setFlags([.fileInherit, .directoryInherit])
```

**Permission Types:**

| POSIX.1e | NFSv4 |
|----------|-------|
| `.read` | `.readData`, `.readNamedAttrs`, `.readAttributes`, `.readACL` |
| `.write` | `.writeData`, `.appendData`, `.writeNamedAttrs`, `.writeAttributes`, `.writeACL`, `.writeOwner` |
| `.execute` | `.execute` |
| | `.delete`, `.deleteChild`, `.synchronize` |

**Tag Types:**

| Tag | Description |
|-----|-------------|
| `.userObj` | File owner |
| `.user` | Specific user (requires qualifier) |
| `.groupObj` | Owning group |
| `.group` | Specific group (requires qualifier) |
| `.mask` | Maximum group class permissions (POSIX.1e) |
| `.other` | All other users (POSIX.1e) |
| `.everyone` | All users (NFSv4) |

---

### Rctl

Swift interface to FreeBSD's rctl(4) resource control subsystem for limiting CPU, memory, and I/O resources per-process, per-user, per-jail, or per-login class.

```swift
import Rctl

// Check if rctl is enabled in the kernel
if Rctl.isEnabled {
    print("rctl is available")
}

// Get resource usage for current process
let usage = try Rctl.getCurrentProcessUsage()
print("CPU time: \(usage["cputime"] ?? "0")")
print("Memory: \(usage["memoryuse"] ?? "0")")

// Get usage for a specific subject
let jailUsage = try Rctl.getUsage(for: .jailName("myjail"))
```

**Adding Resource Limits:**

```swift
import Rctl

// Limit memory for a user to 1GB
try Rctl.limitMemory(Rctl.Size.gb(1), for: .user(1000))

// Limit CPU to 50% for a jail
try Rctl.limitCPU(50, for: .jailName("myjail"))

// Limit open files for a process
try Rctl.limitOpenFiles(256, for: .process(getpid()))

// Limit max processes per user
try Rctl.limitProcesses(100, for: .userName("www"))
```

**Custom Rules:**

```swift
import Rctl

// Create a custom rule with signal action
let rule = Rctl.Rule(
    subject: .loginClass("daemon"),
    resource: .cpuTime,
    action: .signal(SIGXCPU),
    amount: 3600  // 1 hour
)
try Rctl.addRule(rule)

// Rule with per-process limit
let memRule = Rctl.Rule(
    subject: .jail(5),
    resource: .memoryUse,
    action: .deny,
    amount: Rctl.Size.mb(512),
    per: .process
)
try Rctl.addRule(memRule)

// Remove a rule
try Rctl.removeRule(rule)

// Remove all rules for a subject
try Rctl.removeRules(for: .user(1000))
```

**Rule Builder:**

```swift
import Rctl

var builder = Rctl.ruleBuilder()
_ = builder.forSubject(.jailName("webserver"))
_ = builder.limiting(.vmemoryUse)
_ = builder.withAction(.deny)
_ = builder.toAmount(Rctl.Size.gb(4))
_ = builder.per(.process)

if let rule = builder.build() {
    try Rctl.addRule(rule)
}
```

**Query Existing Rules:**

```swift
import Rctl

// Get all rules
let allRules = try Rctl.getRules()

// Get rules for a specific subject
let userRules = try Rctl.getRules(for: .user(1000))

// Parse a rule string
if let rule = Rctl.Rule(parsing: "user:1000:memoryuse:deny=536870912/process") {
    print("Subject: \(rule.subject)")
    print("Resource: \(rule.resource)")
    print("Amount: \(rule.amount)")
}
```

**Process Descriptor Integration:**

```swift
import Rctl
import Descriptors

// Fork a child process with pdfork
let result = try ProcessCapability.fork()

if !result.isChild, var desc = result.descriptor as? ProcessCapability {
    // Get resource usage via process descriptor
    let usage = try Rctl.getUsage(for: desc)
    print("Child CPU: \(usage["cputime"] ?? "0")")

    // Or create a subject from descriptor
    let subject = try Rctl.Subject.process(from: desc)

    // Apply limits to the child process
    try Rctl.limitMemory(Rctl.Size.mb(256), for: desc)
    try Rctl.limitCPU(50, for: desc)
}
```

**Subjects:**

| Subject | Description | Example |
|---------|-------------|---------|
| `.process(pid)` | Specific process | `.process(1234)` |
| `.user(uid)` | User by UID | `.user(1000)` |
| `.userName(name)` | User by name | `.userName("www")` |
| `.loginClass(name)` | Login class | `.loginClass("daemon")` |
| `.jail(jid)` | Jail by JID | `.jail(5)` |
| `.jailName(name)` | Jail by name | `.jailName("myjail")` |

**Resources:**

| Resource | Description |
|----------|-------------|
| `.cpuTime` | CPU time in seconds |
| `.memoryUse` | Resident memory (RSS) |
| `.vmemoryUse` | Virtual memory |
| `.maxProc` | Number of processes |
| `.openFiles` | Open file descriptors |
| `.threads` | Number of threads |
| `.swapUse` | Swap space usage |
| `.pcpu` | CPU percentage (0-100 per CPU) |
| `.readBps` / `.writeBps` | I/O bandwidth |
| `.readIops` / `.writeIops` | I/O operations per second |

**Actions:**

| Action | Description |
|--------|-------------|
| `.deny` | Deny the resource allocation |
| `.log` | Log via syslog |
| `.devctl` | Send notification via devctl |
| `.throttle` | Throttle I/O (for bandwidth limits) |
| `.signal(sig)` | Send signal (SIGTERM, SIGKILL, etc.) |

---

### Cpuset

Swift interface to FreeBSD's cpuset(2) CPU affinity and NUMA domain subsystem.

```swift
import Cpuset

// Get current thread's CPU affinity
let affinity = try Cpuset.getAffinity(for: .currentThread)
print("Running on CPUs: \(affinity.cpus)")

// Get available CPUs
let available = try Cpuset.availableCPUs()
print("Available: \(available)")

// Check system CPU count
let root = try Cpuset.rootCPUs()
print("System has \(root.count) CPUs")
```

**Pinning Threads/Processes:**

```swift
import Cpuset

// Pin current thread to CPU 0
try Cpuset.pinCurrentThread(to: 0)

// Pin to multiple CPUs
try Cpuset.pinCurrentThread(to: [0, 1, 2, 3])

// Pin current process
try Cpuset.pinCurrentProcess(to: 0)

// Reset to all available CPUs
try Cpuset.resetCurrentThreadAffinity()
```

**Working with CPU Sets:**

```swift
import Cpuset

// Create CPU sets
var set = CPUSet()
set.set(cpu: 0)
set.set(cpu: 2)
set.set(cpu: 4)

// From array or range
let fromArray = CPUSet(cpus: [0, 1, 2, 3])
let fromRange = CPUSet(range: 0..<8)

// Set operations
let union = set1.union(set2)
let intersection = set1.intersection(set2)
let difference = set1.subtracting(set2)

// Query
print("CPUs: \(set.cpus)")      // [0, 2, 4]
print("Count: \(set.count)")    // 3
print("First: \(set.first!)")   // 0
print("Empty: \(set.isEmpty)")  // false
```

**NUMA Domain Affinity:**

```swift
import Cpuset

// Get domain policy
let (domains, policy) = try Cpuset.getDomain(for: .currentThread)
print("Policy: \(policy)")  // .roundRobin, .firstTouch, .prefer, .interleave

// Set first-touch allocation (local to running CPU)
try Cpuset.useFirstTouchAllocation()

// Prefer a specific domain
try Cpuset.preferDomain(0)

// Round-robin across domains
try Cpuset.useRoundRobinAllocation()

// Interleave across specific domains
try Cpuset.useInterleaveAllocation(domains: [0, 1])
```

**Process Descriptor Integration:**

```swift
import Cpuset
import Descriptors

// Fork with pdfork
let result = try ProcessCapability.fork()

if !result.isChild, let desc = result.descriptor as? ProcessCapability {
    // Pin child to specific CPUs
    try Cpuset.pin(desc, to: [0, 1])

    // Get child's affinity
    let childAffinity = try Cpuset.getAffinity(for: desc)
}
```

**Named Cpusets:**

```swift
import Cpuset

// Create a new cpuset (inherits from current)
let setId = try Cpuset.create()

// Assign thread to cpuset
try Cpuset.assign(.currentThread, to: setId)

// Get cpuset ID for a target
let id = try Cpuset.getId(level: .cpuset, for: .currentThread)
```

**IRQ and Jail Affinity:**

```swift
import Cpuset

// Get/set IRQ affinity (requires root)
let irqAffinity = try Cpuset.getIRQAffinity(16)
try Cpuset.setIRQAffinity(16, to: CPUSet(cpu: 0))

// Get/set jail affinity (requires root)
let jailAffinity = try Cpuset.getJailAffinity(5)
try Cpuset.setJailAffinity(5, to: CPUSet(cpus: [0, 1]))
```

**Targets:**

| Target | Description |
|--------|-------------|
| `.currentThread` | The calling thread |
| `.currentProcess` | The calling process |
| `.thread(tid)` | Specific thread ID |
| `.process(pid)` | Specific process ID |
| `.cpuset(id)` | Named cpuset |
| `.irq(num)` | IRQ number |
| `.jail(jid)` | Jail ID |
| `.domain(id)` | NUMA domain |

**Levels:**

| Level | Description |
|-------|-------------|
| `.root` | All system CPUs |
| `.cpuset` | Available CPUs for target's cpuset |
| `.which` | Actual mask for specific target |

---

### Netmap

Swift interface to FreeBSD's netmap high-performance packet I/O framework.

Netmap provides direct access to NIC ring buffers, bypassing the kernel network stack for maximum performance. This is useful for packet capture, traffic generation, software switching, and network function virtualization.

```swift
import Netmap

// Open a netmap port on interface em0
var port = try NetmapPort.open(interface: "em0")

// Receive packets
let rxRing = port.rxRing(0)
while !rxRing.isEmpty {
    let slot = rxRing.currentSlot
    let packet = rxRing.bufferData(for: slot)
    // Process packet...
    rxRing.advance()
}
try port.rxSync()

// Transmit packets
let txRing = port.txRing(0)
if txRing.hasSpace {
    var slot = txRing.currentSlot
    txRing.setBuffer(for: &slot, data: packetData)
    txRing.advance()
    try port.txSync()
}
```

**Port Types:**

| Mode | Description |
|------|-------------|
| NIC mode | Direct access to physical NIC rings |
| Host mode | Intercept packets to/from host stack |
| VALE switch | Software L2 switch port |
| Pipe mode | Zero-copy IPC channel |

**VALE Switch Operations:**

```swift
import Netmap

// Attach a port to a VALE switch (creates switch if needed)
let portIndex = try NetmapVALE.attach(switch: "vale0", port: "myport")

// List ports on a switch
let ports = try NetmapVALE.listPorts(switch: "vale0")
for port in ports {
    print("Port \(port.index): \(port.name)")
}

// Create a persistent virtual interface
try NetmapVALE.createInterface(
    name: "vale0:vif0",
    config: NetmapVALE.InterfaceConfig(txRings: 2, rxRings: 2)
)

// Enable busy-polling for low latency
try NetmapVALE.enablePolling(
    name: "vale0:myport",
    config: NetmapVALE.PollingConfig(mode: .singleCPU, firstCPU: 0)
)

// Detach and cleanup
try NetmapVALE.detach(switch: "vale0", port: "myport")
try NetmapVALE.deleteInterface(name: "vale0:vif0")
```

**Advanced Options:**

```swift
// Open with external memory (e.g., hugepages)
let port = try NetmapPort.open(
    interface: "vale0:ext",
    options: .externalMemory(NetmapExternalMemory(
        memory: hugepagePtr,
        bufferCount: 512,
        bufferSize: 2048
    ))
)

// Open with packet header room for encapsulation
let port = try NetmapPort.open(
    interface: "em0",
    options: .offsets(NetmapPacketOffsets.headerRoom(64))
)

// Get port information without registering
let info = try NetmapPort.getInfo(interface: "em0")
print("TX rings: \(info.txRings), RX rings: \(info.rxRings)")
```

**Key Types:**
- `NetmapPort` - Move-only port handle with ring access (~Copyable)
- `NetmapRing` - Ring buffer access for TX/RX operations
- `NetmapSlot` - Individual packet slot in a ring
- `NetmapVALE` - VALE software switch management
- `NetmapRegistrationMode` - Port registration modes
- `NetmapPollEvents` - Poll event flags

---

### Audit

Swift interface to FreeBSD's OpenBSM audit framework for security event logging.

The audit subsystem provides comprehensive logging of security-relevant system events, commonly used for compliance (PCI-DSS, HIPAA) and intrusion detection.

```swift
import Audit

// Check if auditing is enabled
if Audit.isEnabled {
    print("Auditing is active")
}

// Get current audit condition and policy
let condition = try Audit.condition()
let policy = try Audit.policy()

// Get audit statistics
let stats = try Audit.statistics()
print("Records generated: \(stats.generated)")
print("Records dropped: \(stats.dropped)")

// Get/set queue control parameters
var qctrl = try Audit.queueControl()
qctrl.highWater = 200
try Audit.set(queueControl: qctrl)
```

**Submitting Audit Records:**

```swift
import Audit

// Submit a simple audit event
try Audit.submit(
    event: AUE_login,
    message: "User login successful",
    success: true
)

// Submit with custom audit ID
try Audit.submit(
    event: AUE_su,
    auditID: 1000,
    message: "Privilege escalation attempt",
    success: false,
    error: EPERM
)
```

**Process Audit Information:**

```swift
import Audit

// Get/set audit user ID
let auid = try Audit.auditID()
try Audit.set(auditID: 1000)

// Get/set full audit info
var info = try Audit.auditInfo()
info.mask = .all  // Audit everything
try Audit.set(auditInfo: info)
```

**Policy Flags:**

| Policy | Description |
|--------|-------------|
| `.continueOnFailure` | Continue after audit failure |
| `.haltOnFailure` | Halt system on audit failure |
| `.includeArgv` | Include command line arguments in exec events |
| `.includeEnv` | Include environment variables |
| `.includeSequence` | Include sequence numbers |
| `.includePath` | Include path tokens |

**Key Types:**
- `Audit` - Main namespace for audit operations
- `Audit.Condition` - Audit subsystem state
- `Audit.Policy` - Policy flags (OptionSet)
- `Audit.Mask` - Preselection mask for success/failure events
- `Audit.AuditInfo` - Process audit information
- `Audit.Statistics` - Audit subsystem statistics

---

### AgeSignal

Implementation of California AB-1043 age signal protocol for privacy-preserving age verification.

The AgeSignal module provides a daemon (`aged`) and client library for querying user age brackets without revealing exact birthdates. Age is reported in four brackets as required by the legislation.

```swift
import AgeSignal

// Query the current user's age bracket
let client = try await AgeSignalClient.connect()
let result = try await client.queryOwnBracket()

switch result {
case .bracket(let bracket):
    print("Age bracket: \(bracket.humanReadable)")
case .notSet:
    print("Birthdate not configured")
case .permissionDenied:
    print("Not authorized")
case .unknownUser:
    print("User not found")
case .error(let error):
    print("Error: \(error)")
}
```

**Age Brackets:**

| Bracket | Description |
|---------|-------------|
| `.under13` | Under 13 years old |
| `.age13to15` | 13-15 years old |
| `.age16to17` | 16-17 years old |
| `.adult` | 18 years or older |

**Administrative Operations (requires root):**

```swift
import AgeSignal

let client = try await AgeSignalClient.connect()

// Set a user's birthdate
try await client.setBirthdate(
    uid: 1000,
    birthdate: Birthdate(year: 2010, month: 6)
)

// Query another user's bracket (privileged)
let result = try await client.queryBracket(uid: 1000)

// Remove a user's birthdate
try await client.removeBirthdate(uid: 1000)
```

**CLI Tools:**

```bash
# Query own age bracket
agectl query

# Set birthdate (requires root)
sudo agectl set --uid 1000 --year 2010 --month 6

# Start the daemon
sudo aged
```

**Protocol Details:**
- Uses FPC (Free Process Communication) over Unix sockets
- Birthdates stored with year/month only (no day) for privacy
- Daemon runs at `/var/run/aged.sock`
- Database stored in `/var/db/aged`

**Key Types:**
- `AgeSignalClient` - Client for querying age brackets
- `AgeBracket` - Age bracket enumeration
- `Birthdate` - Year/month birthdate (no day for privacy)
- `AgeSignalResult` - Query result with bracket or error

---

### OpenCrypto

Swift interface to FreeBSD's OpenCrypto framework for hardware-accelerated cryptography.

OpenCrypto provides access to kernel cryptographic services via /dev/crypto, automatically leveraging hardware acceleration (AES-NI, SHA extensions) when available.

```swift
import OpenCrypto

// Create crypto context
let crypto = try OpenCrypto()

// AES-256-CBC encryption
let cipher = try crypto.cipher(.aes256CBC, key: key)
let ciphertext = try cipher.encrypt(plaintext, iv: iv)
let decrypted = try cipher.decrypt(ciphertext, iv: iv)

// SHA-256 hashing
let hasher = try crypto.hash(.sha256)
let digest = try hasher.hash(data)

// HMAC-SHA256
let hmac = try crypto.hmac(.sha256, key: key)
let mac = try hmac.authenticate(message)
let valid = try hmac.verify(message, tag: mac)

// AES-GCM authenticated encryption
let aead = try crypto.aead(.aes256GCM, key: key)
let (ciphertext, tag) = try aead.seal(plaintext, nonce: nonce, aad: header)
let plaintext = try aead.open(ciphertext, nonce: nonce, aad: header, tag: tag)
```

**Cipher Algorithms:**

| Algorithm | Key Size | Description |
|-----------|----------|-------------|
| `.aes128CBC` | 16 bytes | AES-128 in CBC mode |
| `.aes256CBC` | 32 bytes | AES-256 in CBC mode |
| `.aes128CTR` | 16 bytes | AES-128 in CTR mode |
| `.aes256CTR` | 32 bytes | AES-256 in CTR mode |
| `.chacha20` | 32 bytes | ChaCha20 stream cipher |

**Hash Algorithms:**

| Algorithm | Digest Size | Description |
|-----------|-------------|-------------|
| `.sha256` | 32 bytes | SHA-256 (recommended) |
| `.sha384` | 48 bytes | SHA-384 |
| `.sha512` | 64 bytes | SHA-512 |
| `.blake2b` | 64 bytes | BLAKE2b |
| `.blake2s` | 32 bytes | BLAKE2s |

**AEAD Algorithms:**

| Algorithm | Key Size | Description |
|-----------|----------|-------------|
| `.aes128GCM` | 16 bytes | AES-GCM (recommended) |
| `.aes256GCM` | 32 bytes | AES-256-GCM |
| `.chacha20Poly1305` | 32 bytes | ChaCha20-Poly1305 |

**Requirements:**
- `/dev/crypto` must exist (load module: `kldload cryptodev`)
- For software fallback: `sysctl kern.cryptodevallowsoft=1`

**Key Types:**
- `OpenCrypto` - Main context for crypto operations
- `CipherSession` - Symmetric encryption/decryption
- `HashSession` - Hashing and HMAC
- `AEADSession` - Authenticated encryption

---

### DTraceCore & DBlocks

Swift interface to FreeBSD's DTrace dynamic tracing framework.

**DTraceCore** provides low-level bindings to libdtrace with move-only handle semantics:

```swift
import DTraceCore

// Open DTrace handle
var handle = try DTraceHandle.open()

// Set buffer sizes
try handle.setOption("bufsize", value: "4m")
try handle.setOption("aggsize", value: "4m")

// Compile and execute a D program
let program = try handle.compile("""
    syscall:::entry
    {
        @[execname] = count();
    }
    """)
try handle.exec(program)

// Start tracing
try handle.go()

// Process trace data
while true {
    let status = handle.work()
    if status == .done || status == .error { break }
    handle.sleep()
}

// Print results and stop
try handle.aggregateSnap()
try handle.aggregatePrint()
try handle.stop()
```

**DBlocks** provides a type-safe Swift DSL for building DTrace scripts:

```swift
import DBlocks

// Simple one-liner: count syscalls for 5 seconds
try DBlocks.run(for: 5) {
    Probe("syscall:::entry") {
        Count(by: "probefunc")
    }
}
```

**Result Builder DSL:**

```swift
// Build complete scripts with Swift syntax
let script = DBlocks {
    BEGIN {
        Printf("Starting trace...")
    }

    Probe("syscall::read:entry") {
        Target(.execname("nginx"))
        Timestamp()
    }

    Probe("syscall::read:return") {
        Target(.execname("nginx"))
        When("self->ts")
        Latency(by: "execname")
    }

    Tick(10, .seconds) {
        Exit(0)
    }

    END {
        Printf("Trace complete")
    }
}

print(script.source)  // View generated D code
try script.run()      // Execute (requires root)
```

**Aggregations:**

```swift
DBlocks {
    Probe("syscall:::entry") {
        // Simple count
        Count()

        // Count by key
        Count(by: "probefunc")

        // Named aggregation with multi-key
        Count(by: ["execname", "probefunc"], into: "calls")

        // Other aggregation functions
        Sum("arg0", by: "execname", into: "bytes")
        Min("arg0", by: "execname")
        Max("arg0", by: "execname")
        Avg("arg0", by: "execname")
        Quantize("arg0", by: "execname")              // Power-of-2 histogram
        Lquantize("arg0", low: 0, high: 100, step: 10, by: "execname")
    }

    END {
        Printa("calls")      // Print specific aggregation
        Clear("calls")       // Clear aggregation
        Trunc("calls", 10)   // Keep top 10
        Normalize("calls", 1_000_000)  // Convert units
    }
}
```

**Variables:**

```swift
DBlocks {
    BEGIN {
        Assign(.global("total"), to: "0")     // Global: total
    }

    Probe("syscall::read:entry") {
        Assign(.thread("ts"), to: "timestamp")  // Thread-local: self->ts
        Assign(.clause("temp"), to: "arg0")     // Clause-local: this->temp
    }

    Probe("syscall::read:return") {
        When("self->ts")
        Assign(.global("total"), to: "total + 1")
    }
}
```

**Target Predicates:**

```swift
// Filter by process attributes
Target(.pid(1234))
Target(.execname("nginx"))
Target(.uid(0))
Target(.gid(100))
Target(.jail(5))
Target(.processNameContains("http"))

// Combine with operators
Target(.execname("nginx") || .execname("apache"))
Target(.execname("postgres") && .uid(70))
Target(!.uid(0))  // Not root

// Custom D predicate
Target(.custom("arg0 > 1024"))
When("arg0 > 0")  // Additional predicate
```

**Special Clauses:**

```swift
DBlocks {
    BEGIN { Printf("Start") }           // Runs once at start
    END { Printa() }                    // Runs once at end
    ERROR { Printf("Error!") }          // On DTrace errors

    Tick(1, .seconds) { Printa() }      // Every second
    Tick(hz: 100) { Count() }           // 100 Hz
    Profile(hz: 997) { Count(by: "execname") }  // CPU sampling
}
```

**Output Actions:**

```swift
Probe("syscall::open:entry") {
    Printf("%s[%d]: %s", "execname", "pid", "copyinstr(arg0)")
    Trace("arg0")
    Stack()                    // Kernel stack trace
    Stack(userland: true)      // User stack trace
}
```

**Predefined Scripts:**

```swift
// Ready-to-use scripts
let script = DBlocks.syscallCounts(for: .execname("postgres"))
let script = DBlocks.fileOpens(for: .uid(0))
let script = DBlocks.cpuProfile(hz: 997)
let script = DBlocks.ioBytes(for: .execname("nginx"))
let script = DBlocks.syscallLatency("read", for: .pid(1234))
```

**Composable Scripts:**

```swift
// Build scripts incrementally
var script = DBlocks()
script.add("syscall:::entry") {
    Count(by: "probefunc")
}
script.merge(DBlocks.syscallCounts())

// Combine scripts with operators
let combined = DBlocks { BEGIN { Printf("Start") } }
             + DBlocks.syscallCounts(for: .execname("nginx"))
             + DBlocks { Tick(5, .seconds) { Exit(0) } }
```

**Session API:**

```swift
// Full control over execution
var session = try DTraceSession.create()
session.output(to: .buffer(buffer))
try session.bufferSize("8m")
try session.jsonOutput()

session.add {
    Probe("syscall:::entry") { Count(by: "probefunc") }
}

try session.run(for: 10)  // Run for 10 seconds

// Or manual control
try session.start()
while session.isRunning {
    _ = session.process()
    session.wait()
}
try session.stop()
try session.printAggregations()
```

**Output Destinations:**

```swift
session.output(to: .stdout)
session.output(to: .stderr)
session.output(to: .file("/tmp/trace.log"))
session.output(to: .null)

let buffer = DTraceOutputBuffer()
session.output(to: .buffer(buffer))
// ... run trace ...
let output = buffer.contents
```

**Key Types:**
- `DTraceHandle` - Low-level libdtrace handle (~Copyable)
- `DTraceSession` - High-level session manager
- `DBlocks` - Type-safe D script builder (result builder)
- `DTraceTarget` - Process targeting predicates
- `Probe`, `BEGIN`, `END`, `Tick`, `Profile` - Clause builders
- `Count`, `Sum`, `Min`, `Max`, `Avg`, `Quantize` - Aggregation functions
- `Printf`, `Trace`, `Stack`, `Timestamp`, `Latency` - Action helpers

---

### CMacLabelParser

Dependency-free C library for parsing MAC labels.

```c
#include <maclabel_parser.h>

// Parse label data
maclabel_parser_t parser;
maclabel_parser_init(&parser, label_data, label_len);

// Iterate over key-value pairs
const char *key, *value;
size_t key_len, value_len;

while (maclabel_parser_next(&parser, &key, &key_len, &value, &value_len) == 0) {
    printf("%.*s = %.*s\n", (int)key_len, key, (int)value_len, value);
}
```

This library is designed for use in kernel modules, boot loaders, or other environments where Swift or the full FreeBSDKit framework is not available.

---

## Design Principles

### Move-Only Types (`~Copyable`)

All descriptor types are move-only to prevent common resource management bugs:

```swift
var file = FileCapability(fd)
let copy = file  // Ownership transfers, 'file' is now invalid
// file.read()   // Compile error: 'file' used after being consumed
```

### Explicit Ownership

Resources can be consumed to extract the underlying handle:

```swift
var socket = SocketCapability(fd)
let rawFd: Int32 = socket.take()  // Socket is consumed, caller owns fd
// Caller is now responsible for closing rawFd
```

### Capability-Based Security

The framework is designed around Capsicum's capability model:

```swift
// Open resources before entering capability mode
var configDir = try DirectoryCapability.open(path: "/etc/myapp")
var dataDir = try DirectoryCapability.open(path: "/var/myapp")
var logFile = try FileCapability.open(path: "/var/log/myapp.log", flags: [.writeOnly, .append])

// Limit rights to minimum needed
_ = configDir.limit(rights: CapsicumRightSet(rights: [.read, .lookup]))
_ = dataDir.limit(rights: CapsicumRightSet(rights: [.read, .write, .lookup, .create]))
_ = logFile.limit(rights: CapsicumRightSet(rights: [.write]))

// Enter sandbox
try Capsicum.enter()

// Now only operations on these descriptors with their limited rights are allowed
```

---

## C Bridge Modules

Several C modules provide access to macros and inline functions that Swift cannot import directly:

| Module | Purpose |
|--------|---------|
| `CCapsicum` | Capsicum rights macros and helper functions |
| `CCasper` | Casper (libcasper) service wrappers |
| `CJails` | Jail flag constants and wrapper functions |
| `CProcessDescriptor` | Process descriptor (pdfork) functions |
| `CEventDescriptor` | Event notification functions |
| `CDeviceIoctl` | Device ioctl constants (FIONREAD, DIOCGSECTORSIZE, etc.) |
| `CProcctl` | Process control constants and structures |
| `CACL` | ACL constants and type definitions |
| `CRctl` | Resource control syscall wrappers |
| `CCpuset` | CPU affinity macros and syscall wrappers |
| `CSignal` | Signal handling macros |
| `CExtendedAttributes` | Extended attribute constants |
| `CDTrace` | DTrace libdtrace wrappers and constants (used by DTraceCore/DBlocks) |
| `CNetmap` | Netmap ioctl wrappers and ring buffer access macros |
| `CAudit` | OpenBSM audit syscall wrappers and constants |
| `COpenCrypto` | OpenCrypto /dev/crypto ioctl wrappers |

---

## Testing

```bash
swift test
```

Tests require root privileges for some Capsicum and jail functionality. Tests that require elevated privileges are skipped when running as a regular user.

---

## License

BSD-2-Clause

---

## Non-Goals

FreeBSDKit intentionally does **not**:

- Provide cross-platform compatibility
- Abstract away FreeBSD-specific semantics
- Support non-FreeBSD operating systems

This project embraces FreeBSD's identity and unique features rather than hiding them behind portable abstractions.
