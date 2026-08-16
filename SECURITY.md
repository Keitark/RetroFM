# Security and safety reporting

Please do not put credentials, tokens, private file paths, private board
identifiers, SD-card images, copyrighted music, or import archives in a public
issue, pull request, log, or waveform attachment.

If you find a possible security problem, use GitHub's private vulnerability
reporting channel for the repository when available. Otherwise contact the
repository owner privately with a minimal description, affected revision, and
safe reproduction steps. Do not disclose an exploitable detail publicly until
there is an agreed fix or mitigation.

RetroFM is prototype hardware. The audio connector is a line-level prototype,
not a protected headphone or passive-speaker output. Electrical continuity,
voltage, polarity, loading, and overshoot must be checked on the actual board
before connecting external equipment. Do not infer electrical or audible
acceptance from a successful compile, simulation, or package step.

When reporting a suspected issue, separate the evidence state: host test,
RTL simulation, Vivado/Vitis build, or physical-board observation. Include the
exact command/tool version and a sanitized log or hash where useful, while
keeping private inputs and generated binary products out of the repository.
