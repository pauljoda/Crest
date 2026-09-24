namespace CrestCore.Contracts;

/// An intent about the pages this device hosts: which tab or transient request
/// owns each, and which engine hosts it. The platform names each page with an
/// identity it makes, which does not depend on the engine.
public abstract record PageIntent : Intent;
