# Media source of truth: Lightroom Classic and Immich

## Status

planning — draft for [#2143](https://github.com/isejalabs/homelab/issues/2143), Phase 0 of the Immich implementation ([#413](https://github.com/isejalabs/homelab/issues/413)). The options and the proposed decision are based on the current workflow and the Immich documentation (checked on 2026-11-02 against the `main` branch of [`immich-app/immich`](https://github.com/immich-app/immich/tree/main/docs/docs)). The decision is not settled yet: it depends on the owner's answers to the [open questions](#open-questions) and on the [proof of concept](#proof-of-concept) on the `qa` instance. The ADR is rewritten in place once the PoC is done (the same planning-draft exception as [ADR 0016](0016-identity-and-web-sso.md)) and becomes `current` when the full import ([#2151](https://github.com/isejalabs/homelab/issues/2151)) has run.

## Context

### Current workflow

- 110,000+ photos and videos, growing by 4,000–10,000 per year, catalogued in Lightroom Classic (LrC) on the owner's Mac. The originals are on the NAS `fiona`, which stays the media datastore.
- **Camera media** are copied to the Mac and imported by LrC.
- **Phone media** are uploaded by Lightroom Mobile to Adobe Cloud, into one destination folder per person (that is how the creator is attributed later), downloaded by LrC on the Mac, then deleted from Adobe Cloud to save space.
- LrC syncs everything except videos back to Adobe Cloud as Smart Previews, which do not count against the 20 GB plan. Adobe Cloud is therefore no complete online archive: the videos are missing.
- Images are mostly kept as they are. LrC is needed for RAW development and for the occasional edit.

Immich should become the online archive for photos **and** videos and replace Lightroom Mobile for uploads, so that phone media can be shared quickly. Only one tool can be the master of a given asset; this ADR decides which one, for which media, and how media and metadata flow between the two.

### What Immich does with a library

Immich knows two kinds of library, and they behave differently in every point that matters here:

| | Upload library | External library |
| --- | --- | --- |
| How assets get in | Uploaded (mobile app, web, CLI) and copied into Immich's own folder | Immich scans an existing folder ("import paths"); nothing is copied |
| Folder layout | Immich's [storage template](https://docs.immich.app/administration/storage-template), e.g. `<storage label>/<year>/<date>/<file>`; a per-user storage label puts each person's uploads into their own folder | Unchanged, as on disk |
| Owner | The uploading user | One user per library, chosen at creation and [not changeable later](https://docs.immich.app/features/libraries) |
| Duplicates | Rejected by file hash, but only within the same library | Not checked; the same file can appear twice in the timeline, also once as upload and once as external asset ([FAQ](https://docs.immich.app/FAQ#what-happens-to-duplicates-in-external-libraries)) |
| Changes on disk | Immich does not scan its own folder | Picked up by a rescan (nightly by default, interval configurable); file watching is experimental and "likely won't work" on a network share |
| File moved or renamed on disk | Not expected | Treated as deleted plus new asset: everything stored only in Immich (albums, description, faces) is lost for it |
| Delete in Immich | Trash, then the original file is deleted when the trash is emptied (30 days by default) | Read-write mount: same as upload. Read-only mount: the asset comes back after the trash is emptied |
| Metadata edits in Immich | Written to the database and to an `.xmp` sidecar | Read-write: same. Read-only: not possible (description, rating, date, location); see [`immich-app/immich#10538`](https://redirect.github.com/immich-app/immich/issues/10538) |

Immich never rewrites an original file; edits go to the database and to XMP sidecars, and its own editing (crop, rotate, mirror) is non-destructive ([FAQ](https://docs.immich.app/FAQ#does-immich-change-the-file), [editing](https://docs.immich.app/features/editing)). It does delete originals when a trashed asset's trash is emptied, if it has write access.

### Metadata that can flow from LrC to Immich

Immich reads only a few fields from XMP sidecars ([XMP sidecars](https://docs.immich.app/features/xmp-sidecars)): description (`dc:description`), rating (`xmp:Rating`), capture date, GPS position and tags (`digiKam:TagsList`, then `lr:HierarchicalSubject`, then `IPTC:Keywords`, so LrC's hierarchical keywords are usable). Everything else, including creator, IPTC fields, pick flags, colour labels, collections and develop settings, stays in LrC and is not visible or searchable in Immich. A sidecar must be named `IMG_0001.jpg.xmp` or `IMG_0001.xmp`; LrC writes the second form.

LrC writes XMP sidecars only for proprietary RAW files. For JPEG, HEIC, TIFF and DNG it writes the metadata into the file itself, which changes the original. Whether Immich picks up such in-file metadata on a rescan, and keeps it the same asset, is a PoC item.

There is no metadata flow from Immich to LrC. The LrC plugin [`bmachek/lrc-immich-plugin`](https://github.com/bmachek/lrc-immich-plugin) offers export to Immich, a publish service that keeps LrC collections and Immich albums aligned, and import of Immich albums into LrC; its README mentions no metadata sync and no handling of deletes.

### Other facts that shape the choice

- Immich has no automatic RAW + JPEG pairing. Both files become separate assets; they can be stacked by hand or through the duplicates utility. Common camera RAW formats (CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2 and others) are supported ([source](https://github.com/immich-app/immich/blob/main/server/src/utils/mime-types.ts)). Exclusion patterns per external library can hide RAWs, e.g. `**/*.{cr3,nef}`.
- Faces, albums, favourites, shares and the archive flag exist only in the Immich database, whichever library type the asset is in. They survive only as long as the asset keeps its path (external) or is not deleted (upload).
- Partner sharing lets each person see the other's timeline; an asset still has exactly one owner.
- Thumbnails and transcoded videos add 10–20 % to the library size ([requirements](https://docs.immich.app/install/requirements)); they are regenerable.

## Options considered

### 1. LrC is master for everything; Immich is viewer and phone inbox

Phone media are uploaded to Immich and imported by LrC from there instead of from Adobe Cloud. LrC copies or moves them into its own folder tree, which Immich indexes as a read-only external library. The upload copy is then deleted in Immich, or it stays and the same photo shows twice.

- Pro: One master, one catalog, one folder tree, as today. Ratings, keywords and captions reach Immich through XMP.
- Con: The quick share made right after upload is attached to the upload asset. Deleting that asset after the LrC import breaks the share and loses any album membership and description given in Immich; keeping it means duplicates, which Immich does not detect across libraries.
- Con: Phone media take a manual step (LrC import) before they are in the archive; until then the upload library is the only copy on `fiona`.
- Con: Albums made in Immich on LrC-managed files break whenever LrC moves or renames a file or folder.

### 2. Master by origin: Immich for phone media, LrC for camera media

Each asset has exactly one master, decided by where it came from and visible from its folder:

- **Phone media** (new uploads): Immich upload library on `fiona`, laid out by the storage template with one storage label per person, for example `upload/sebi/2026/2026-11-02/IMG_1234.HEIC`. Immich is the master; the creator is the uploading account. When an edit is needed, LrC reads the file from a read-only share of the upload dataset, and the result goes back to Immich through the plugin (stacked with the original).
- **Camera media and the existing library** (including the phone media imported into LrC so far): LrC folders on `fiona`, indexed by Immich as a read-only external library. LrC is the master and writes metadata to XMP; Immich only shows it.

- Pro: Upload assets are permanent in Immich, so quick shares and albums keep working. No duplicates by construction, because nothing is in both trees.
- Pro: LrC keeps what it is good at (RAW development, editing, keyword management) for the media that need it, without its workflow changing.
- Pro: Reversible: the upload library is plain files with sidecars under a readable folder layout and can be imported into LrC later; the external library can later be moved into Immich (option 3) if LrC fades out.
- Con: Two catalogs: LrC no longer sees new phone media unless they are added on purpose. A search across everything happens in Immich, not in LrC.
- Con: The upload dataset becomes primary storage of originals, so its backup must be as strong as the LrC library's.
- Con: Deleting a camera photo has to happen in LrC (Immich cannot delete from a read-only library); deleting a phone photo happens in Immich.

### 3. Immich is master for everything; LrC is a developing tool

The existing library is imported once into Immich's upload library (copied or moved), the LrC catalog is frozen as history, camera media go to Immich directly, and LrC is used only to develop RAWs and export the result to Immich.

- Pro: One master, one catalog, the full Immich feature set (metadata edits, deletes, sidecars) for every asset.
- Con: Immich lacks what LrC offers for organising (pick flags, colour labels, smart collections, keyword hierarchy management, real editing); for RAW development every image needs an export round trip.
- Con: LrC-only metadata is lost or frozen; a one-off import of 110,000+ assets either copies them (double space) or moves them away from where LrC expects them.
- Con: Hardest to undo.

### Criteria

| | 1 LrC master | 2 Master by origin | 3 Immich master |
| --- | --- | --- | --- |
| Originals safe from Immich | yes (read-only) | camera: yes (read-only); phone: Immich owns them, ZFS snapshots and trash as undo | Immich owns them |
| Quick sharing from the phone | only until LrC import | yes | yes |
| Duplicates | likely | none by construction | none |
| Creator attribution | LrC folders, as today | phone: account and folder; camera: folder | account |
| Effort per new phone photo | upload + LrC import + cleanup | upload only | upload only |
| RAW development | LrC | LrC | LrC + export |
| Videos in the online archive | yes | yes | yes |
| Reversibility | high | high | low |

## Decision

**Proposed, pending the PoC and the open questions:** option 2, master by origin.

It is the only option in which quick sharing, one master per asset and the existing LrC workflow for camera media all hold at the same time. Option 1 conflicts with how Immich identifies assets (shares and albums do not survive the hand-over to LrC, and Immich does not deduplicate across libraries). Option 3 is a possible later step from option 2, not a starting point.

Rules that go with it:

1. The LrC library is mounted **read-only** into every Immich environment ([#2144](https://github.com/isejalabs/homelab/issues/2144)). Immich never deletes or rewrites a file LrC owns.
2. LrC writes metadata to XMP automatically ("Automatically write changes into XMP"), so ratings, keywords and captions reach Immich on the next rescan. Metadata for these assets is edited in LrC, not in Immich.
3. LrC does not move or rename folders or files once Immich has indexed them; a reorganisation counts as a migration and is planned like one, because it drops Immich albums and faces for the moved assets.
4. Phone media live in the Immich upload library, one storage label per person. LrC accesses them only read-only and never imports them by copy or move.
5. Albums for sharing are made in Immich, for both kinds of media. LrC collections that should be visible in Immich are published through the plugin.
6. Deletes happen in the master: LrC for camera media, Immich for phone media.

## Open questions

For the owner, before the PoC:

- Do you want new phone media in the LrC catalog at all (for search, ratings, keywords), or is Immich enough for them? If LrC must see them, option 2 needs a defined "add without import" step, and option 1 becomes worth a second look.
- How are the historical phone media laid out in the LrC tree today, per person? This decides whether there is one external library (owner `sebi`, shared to the family) or one per person.
- Is "Automatically write changes into XMP" already enabled in LrC? Enabling it rewrites the metadata of all JPEG/HEIC files in the library once, which also means a full re-backup of those files on `fiona`.
- Which RAW formats and RAW + JPEG pairs are in the library, and should RAWs be visible in Immich or hidden by an exclusion pattern?
- Which pick flags, colour labels or collections carry meaning that must be visible in Immich (they do not reach it through XMP)?

## Proof of concept

Runs on the `qa` instance ([#2146](https://github.com/isejalabs/homelab/issues/2146)) against a copy of the library, never against the live data. Pass criteria are in brackets.

1. **Subset:** copy one year (about 5,000 assets with RAW, RAW + JPEG pairs, HEIC, Live Photos and videos) to a test dataset on `fiona`, together with the matching part of an LrC catalog copy.
2. **External library, read-only:** index the subset. [All assets appear; counts match the files on disk minus sidecars.]
3. **XMP from LrC:** in the catalog copy, change rating, keywords, caption and GPS on a RAW, a JPEG and a HEIC; let LrC write the metadata; rescan. [Changes appear in Immich; the asset keeps its ID, albums and faces.]
4. **RAW + JPEG pair:** check which asset an `IMG_0001.xmp` sidecar is applied to when `IMG_0001.CR3` and `IMG_0001.JPG` sit side by side. [Documented; no wrong metadata on the JPEG.]
5. **Move in LrC:** move one folder in LrC; rescan. [Confirms the documented loss of Immich-only metadata, so rule 3 is justified.]
6. **Phone upload:** upload from two accounts with storage labels. [Folder layout as designed; owner and partner sharing as expected; Live Photos complete.]
7. **Edit round trip:** add an uploaded HEIC to LrC from a read-only share, edit it, export it with the plugin, stack it with the original. [Works without writing to the upload dataset; the effort per photo is acceptable to the owner.]
8. **Deletes:** delete a file in LrC and rescan; trash and empty the trash for an external and an uploaded asset in Immich. [External asset reappears or goes to trash as documented; uploaded original is deleted and can be restored from a ZFS snapshot.]
9. **Plugin:** publish a collection as an album and import an Immich album into LrC. [Record what is lost.]
10. **Sizing input:** record thumbnail and transcode size per asset and processing time, for [#2147](https://github.com/isejalabs/homelab/issues/2147).

The inventory of the real library (asset count and size per type and year, folder layout, LrC metadata settings) is gathered before the PoC and recorded in [#2143](https://github.com/isejalabs/homelab/issues/2143).

## Consequences

- `fiona` needs, per environment, a writable dataset for the upload library and its cache and a read-only export of the LrC library; the upload dataset holds originals and is backed up offsite like the LrC library ([#2144](https://github.com/isejalabs/homelab/issues/2144)).
- The Immich database is the only place where albums, faces and shares exist, for both kinds of media. Losing it does not lose photos but does lose that organisation, which is why the database backup and restore drill ([#2145](https://github.com/isejalabs/homelab/issues/2145)) come before any real import.
- Lightroom Mobile is replaced for uploads ([#2150](https://github.com/isejalabs/homelab/issues/2150)); the Adobe Cloud download step for phone media goes away.
- The existing library is indexed, not imported: the full "import" in [#2151](https://github.com/isejalabs/homelab/issues/2151) is a scan of the read-only external library, so it needs compute and thumbnail space but no copy of the originals.
- A later move to option 3 stays possible: the external library can be imported into the upload library in batches once LrC is no longer used for camera media.
