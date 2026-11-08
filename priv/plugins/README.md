# The plugin catalog

The installable plugins the platform offers (brain#68, seshat#47; the
plugin spec's door one: data, not code). A plugin enters this folder the
way code enters the repository, by review; it enters a resident's life
only when she and her witness both agree to install it, and turns on
only when both agree again. Either of them may switch it off alone.

Each plugin is a folder named by its key (lowercase letters, digits and
`-`, starting with a letter):

    <key>/
      plugin.json   {"name": "...", "about": "...", "author": "...",
                     "version": "...", "tokens": 400}
      files/        the markdown files it puts in front of the resident
                    (lowercase names ending in .md)

`tokens` is the share of her context its section may take (at most
4,000); past it the section says how many files it left out. Installing
writes the files to `plugins/<key>/` in her library with `PLUGIN.md`, the
lockfile pinning their digest; a change here later is offered as a newer
version and taken only by a removal and an install, both parties'.
