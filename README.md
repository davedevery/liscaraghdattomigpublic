# Liscara update feed

This public repository is the update feed for the Liscaragh Migrate
(Liscaragh Software). The app's **Help > Check for updates** reads `update.json` here.

- `update.json` - a signed descriptor: version, notes, and the files to apply (each with a SHA256).
- `files/<version>/` - the shipped files for that version.

`update.json` is signed with Liscaragh's build-integrity key and every file is pinned by SHA256
inside that signed descriptor, so the app refuses anything that is not a genuine, unaltered
Liscaragh release. Updating never touches the licence, connection settings, certificate or jobs
(they live outside the install folder).

**Nothing secret ever belongs here:** no private keys, no `.pfx`, no credentials. Public files only.
