# Third-party dependencies

The MIT license in this repository covers this project's own code. Dependencies
retain their respective licenses and copyright notices; this project does not
relicense their code or fonts.

The validated runtime dependency set includes:

| Dependency | License family |
| --- | --- |
| Flutter SDK and flutter_web_plugins | BSD-3-Clause (Flutter SDK license) |
| plugin_platform_interface | BSD-3-Clause |
| web | BSD-3-Clause |
| file_picker | MIT |
| cupertino_icons (example only) | MIT |

Android also uses AndroidX and Kotlin artifacts, which retain the notices in
their published artifacts. Test and development tools have their own licenses.
Consult the actual resolved dependency versions and their bundled license files;
the list above is not a replacement for those notices. Flutter collects package
licenses into the application's license registry. Keep applicable notices when
redistributing dependencies separately or changing the build/packaging process.

Test videos were generated locally for this project; their generator scripts and
fixture documentation accompany the tests. Flutter renderer binaries copied for
local browser testing are excluded from this package's publication archive.
