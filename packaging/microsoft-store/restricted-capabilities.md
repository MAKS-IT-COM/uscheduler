# Microsoft Store restricted capabilities

Paste into Partner Center → Submission options. This product declares only `runFullTrust`.

The field holds 500 characters. [App capability declarations](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations#special-and-restricted-capabilities) says a package with a full-trust app must declare `runFullTrust` or it cannot be installed. A full-trust app uses entry point `Windows.FullTrustApplication` and runs at medium integrity, outside an AppContainer.

## runFullTrust

Why do you need the `runFullTrust` capability, and how will it be used in your product?

```text
MaksIT UScheduler is a full-trust Win32 app (.NET, Avalonia) packaged as MSIX. Windows.FullTrustApplication runs at medium integrity as the signed-in user, outside an AppContainer. runFullTrust is required for this package to install.

Used to run scheduled PowerShell scripts and console programs, and to read and write scripts, logs, and settings under C:\MaksIT and %ProgramData%\MaksIT\UScheduler. Registering the service asks you to approve elevation. No device capabilities.
```

Store listing text is in [description.md](description.md), [product-features.md](product-features.md), [keywords.md](keywords.md), and [additional-info.md](additional-info.md).
