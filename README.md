Ocaml 4.00.0-beta2 - Community maintained Architectures
=======================================================

For the 4.00 line of OCaml compiler the core developers decided to jettison
some of the less commonly used architectures (Alpha, HPPA, IA64 -aka Itanium-
and MIPS) to focus mainly on x86/amd64 and ARM targets. Also, some other
architectures were not receiving their share of care, leading to some
courageous volunteers to maintain their own improved backends.

This repository aims to collect in a central location all these community
maintained architectures in addition to restore the archs that were pruned for
the 4.00 release.

Following are some details about the currently available additional
architectures.

IA64
----

To be done

Mips
----

Compared to the legacy mips backend, targeting the Irix OS, this one is for
GNU/linux on MIPS, either big or little endian. The ABI used is n32, as in the
past.

It's well tested on the Loongson processors but should work on other variants
too.

PPC64
-----

To be done

