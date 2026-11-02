# Media source of truth: Lightroom Classic and Immich

## Status

planning — draft for [#2143](https://github.com/isejalabs/homelab/issues/2143), Phase 0 of the Immich implementation ([#413](https://github.com/isejalabs/homelab/issues/413)). The options and the proposed decision are based on the current workflow, the owner's answers of 2026-11-02 (see [Owner's input](#owners-input)) and the Immich documentation (checked on 2026-11-02 against the `main` branch of [`immich-app/immich`](https://github.com/immich-app/immich/tree/main/docs/docs)). The owner accepted the decision on 2026-11-02; it still has to hold in the [proof of concept](#proof-of-concept) on the `qa` instance, and the remaining [open questions](#open-questions) are settled there or in the named issues. The ADR is rewritten in place once the PoC is done (the same planning-draft exception as [ADR 0016](0016-identity-and-web-sso.md)) and becomes `current` when the full import ([#2151](https://github.com/isejalabs/homelab/issues/2151)) has run.

## Context

### Current workflow

- 110,000+ photos and videos, growing by 4,000–10,000 per year, catalogued in Lightroom Classic (LrC) on the owner's Mac. The originals are on the NAS `fiona`, which stays the media datastore; `fiona` is backed up on-site and off-site with borgbackup.
- The LrC library is organised by date folders, `YEAR/MONTH/DAY-Title`. The creator of a photo is recorded in the IPTC creator field and through collections, not through the folder.
- LrC writes metadata to XMP automatically ("Automatically write changes into XMP" is enabled).
- **Camera media** are copied to the Mac and imported by LrC. The RAW formats in the library are `.NEF` (Nikon) and `.ARW` (Sony); RAWs mostly have no JPEG next to them.
- **Phone media** are uploaded by Lightroom Mobile to Adobe Cloud, into one destination folder per person, downloaded by LrC on the Mac, then deleted from Adobe Cloud to save space.
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

Immich reads only a few fields from XMP sidecars ([XMP sidecars](https://docs.immich.app/features/xmp-sidecars)): description (`dc:description`), rating (`xmp:Rating`), capture date, GPS position and tags (`digiKam:TagsList`, then `lr:HierarchicalSubject`, then `IPTC:Keywords`, so LrC's hierarchical keywords are usable). Everything else, including the IPTC **creator**, pick flags, colour labels, collections and develop settings, stays in LrC and is not visible or searchable in Immich. A sidecar must be named `IMG_0001.jpg.xmp` or `IMG_0001.xmp`; LrC writes the second form.

LrC writes XMP sidecars only for proprietary RAW files. For JPEG, HEIC, TIFF and DNG it writes the metadata into the file itself. Whether Immich reads that in-file metadata on a rescan, and keeps it the same asset, is a PoC item.

There is no metadata flow from Immich to LrC. The LrC plugin [`bmachek/lrc-immich-plugin`](https://github.com/bmachek/lrc-immich-plugin) offers export to Immich, a publish service that keeps LrC collections and Immich albums aligned, and import of Immich albums into LrC; its README mentions no metadata sync and no handling of deletes. Its publish service uploads rendered copies, so it does not put the external-library asset itself into an album.

### RAW files

Immich renders a RAW file on its own, from the RAW data or, with "Prefer embedded preview", from the camera's embedded JPEG ([system settings](https://docs.immich.app/administration/system-settings)). LrC develop settings (exposure, white balance, crop) are stored as `crs:` fields in the XMP sidecar, which Immich does not read. So Immich shows an unedited RAW roughly as the camera would, and an edited RAW **without** its edits, including the crop. Immich has no automatic RAW + JPEG pairing; two files become two assets that can be stacked by hand, through the duplicates utility, or through the API. `.NEF` and `.ARW` are both supported ([source](https://github.com/immich-app/immich/blob/main/server/src/utils/mime-types.ts)).

### Users and sharing

- An external library has exactly one owner. [Partner sharing](https://docs.immich.app/features/partner-sharing) is one-way, and it does **not** include people and facial recognition data or the partner's existing albums; it can also show duplicates on the timeline. A family member who sees the historical library through partner sharing therefore cannot browse it by person.
- Faces, albums, favourites, shares and the archive flag exist only in the Immich database, whichever library type the asset is in. They survive only as long as the asset keeps its path (external) or is not deleted (upload).
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

- **Phone media** (new uploads): Immich upload library on `fiona`, laid out by the storage template with one storage label per person, for example `upload/sebi/2026/2026-11-02/IMG_1234.HEIC`. Immich is the master; the creator is the uploading account. LrC does not catalog them; for a rare edit, LrC reads the file from a read-only share and the result goes back to Immich through the plugin.
- **Camera media and the existing library** (including the phone media imported into LrC so far): LrC folders on `fiona`, indexed by Immich as a read-only external library. LrC is the master and writes metadata to XMP; Immich only shows it.

- Pro: Upload assets are permanent in Immich, so quick shares and albums keep working. No duplicates by construction, because nothing is in both trees.
- Pro: LrC keeps what it is good at (RAW development, editing, keyword management) for the media that need it, without its workflow changing.
- Pro: Reversible: the upload library is plain files with sidecars under a readable folder layout and can be imported into LrC later; the external library can later be moved into Immich (option 3) if LrC fades out.
- Con: Two catalogs: LrC no longer sees new phone media. A search across everything happens in Immich, not in LrC.
- Con: The upload dataset becomes primary storage of originals, so its backup must be as strong as the LrC library's.
- Con: Deleting a camera photo has to happen in LrC (Immich cannot delete from a read-only library); deleting a phone photo happens in Immich.

### 3. Immich is master for everything; LrC is a developing tool

The existing library is imported once into Immich's upload library (copied or moved), the LrC catalog is frozen as history, camera media go to Immich directly, and LrC is used only to develop RAWs and export the result to Immich.

- Pro: One master, one catalog, the full Immich feature set (metadata edits, deletes, sidecars) for every asset.
- Con: Immich lacks what LrC offers for organising (smart collections, keyword hierarchy management, real editing); for RAW development every image needs an export round trip.
- Con: LrC-only metadata is lost or frozen; a one-off import of 110,000+ assets either copies them (double space) or moves them away from where LrC expects them.
- Con: Hardest to undo.

### Criteria

| | 1 LrC master | 2 Master by origin | 3 Immich master |
| --- | --- | --- | --- |
| Originals safe from Immich | yes (read-only) | camera: yes (read-only); phone: Immich owns them, ZFS snapshots and trash as undo | Immich owns them |
| Quick sharing from the phone | only until LrC import | yes | yes |
| Duplicates | likely | none by construction | none |
| Creator attribution | IPTC creator, not visible in Immich without a keyword | phone: account; camera: keyword derived from the IPTC creator | account |
| Effort per new phone photo | upload + LrC import + cleanup | upload only | upload only |
| RAW development | LrC | LrC | LrC + export |
| Videos in the online archive | yes | yes | yes |
| Reversibility | high | high | low |

## Owner's input

Answers of 2026-11-02:

1. **Phone media in LrC:** not needed; Immich is enough for them. This removes the main reason to consider option 1.
2. **Layout and creator:** folders are `YEAR/MONTH/DAY-Title`; the creator is in the IPTC creator field and in collections. The historical library therefore becomes **one external library**, owned by one account, with the creator carried as a tag.
3. **XMP:** writing is already enabled, so ratings, keywords and captions of RAW files are in sidecars and those of JPEG/HEIC in the files. Backup of `fiona` is borgbackup, on-site and off-site.
4. **RAW:** `.NEF` (Nikon) and `.ARW` (Sony; first given as `.CRW`, corrected by the owner the same day). RAWs stay visible; there is mostly no JPEG next to them, and Immich does not apply LrC develop settings.
5. **Pick flags, colour labels:** not needed. **Collections** should become Immich albums, otherwise they are lost.
6. **Renditions:** in a separate rendition tree, not next to the RAWs, kept current by an LrC publish service.
7. **Owner of the historical library:** a dedicated shared `family` account, not a personal one (first given as `sebi`, revised the same day). People/faces and memories belong to the account that owns the assets, and partner sharing does not carry them, so a shared account is the only way for the whole family to browse the historical library by person today. New media stay with the individual accounts. The owner hopes that a later Immich release shares people/faces and memories across accounts.

## Decision

**Accepted by the owner on 2026-11-02, to be confirmed by the PoC:** option 2, master by origin.

It is the only option in which quick sharing, one master per asset and the existing LrC workflow for camera media all hold at the same time. Option 1 conflicts with how Immich identifies assets (shares and albums do not survive the hand-over to LrC, and Immich does not deduplicate across libraries). Option 3 is a possible later step from option 2, not a starting point.

Rules that go with it:

1. The LrC library is mounted **read-only** into every Immich environment ([#2144](https://github.com/isejalabs/homelab/issues/2144)) as one external library, owned by the shared `family` account. Immich never deletes or rewrites a file LrC owns. New media (phone uploads) belong to the individual accounts; the creator of a new asset is its owner.
2. LrC keeps writing metadata to XMP automatically, so ratings, keywords and captions reach Immich on the next rescan. Metadata for these assets is edited in LrC, not in Immich.
3. LrC does not move or rename folders or files once Immich has indexed them; a reorganisation counts as a migration and is planned like one, because it drops Immich albums and faces for the moved assets.
4. Phone media live only in the Immich upload library, one storage label per person. LrC does not catalog them.
5. **Creator as keyword:** LrC assigns a keyword such as `Creator|<name>` to every photo, derived once from the IPTC creator field (and the per-person collections where the field is empty) and kept up for new imports. Immich shows it as a tag, which is searchable and works for every viewer.
6. **Collections become albums once:** the existing LrC collections are turned into Immich albums of the external-library assets, by matching each collection's file paths to Immich assets through the API, not by publishing copies. After that, albums are made in Immich, for both kinds of media.
7. **RAW renditions only where needed, in a separate tree:** an unedited RAW is shown as Immich renders it. A RAW with LrC adjustments (an LrC smart collection "has adjustments") gets a rendered JPEG exported by LrC into a rendition tree that mirrors the library's folders (`renditions/YEAR/MONTH/DAY-Title/<name>.jpg`), so LrC's own folders stay unchanged and the RAW's sidecar is never next to a JPEG of the same name. The tree is a second read-only external library, also owned by `family`, so a rendition and its RAW belong to the same account; each rendition is stacked with its RAW in Immich, rendition on top, matched by folder and base name. The tree is filled and kept current by an LrC **publish service** (LrC's "Hard Drive" service or a plugin), so a later edit re-exports the rendition without a manual step. The PoC checks that the service can keep the folder layout; if it cannot, renditions are matched to their RAWs by file name and capture time instead.
8. Deletes happen in the master: LrC for camera media, Immich for phone media.

## Open questions

- How people use the `family` account without weakening authorization: logging in to it directly means a shared credential (and it does not fit per-person SSO, [#1768](https://github.com/isejalabs/homelab/issues/1768)); partner sharing from `family` to each person keeps individual logins but loses people/faces again. Options to weigh in [#2150](https://github.com/isejalabs/homelab/issues/2150), together with the notes from [this thread on family setups](https://www.reddit.com/r/immich/comments/1t81o6c/family_immich_setup_own_library_per_user_or/).
- Revisit trigger: if Immich starts sharing people/faces and memories across accounts, re-check whether the historical library should move to a personal owner or stay with `family`.
- Collection-to-album migration (rule 6): check for an existing community tool that reads the LrC catalog before writing one ("Reuse before you build").

## Proof of concept

Runs on the `qa` instance ([#2146](https://github.com/isejalabs/homelab/issues/2146)) against a copy of the library, never against the live data. Pass criteria are in brackets.

1. **Subset:** copy one year (about 5,000 assets with `.NEF` and `.ARW`, edited and unedited RAWs, HEIC, Live Photos and videos) to a test dataset on `fiona`, together with the matching part of an LrC catalog copy.
2. **External library, read-only:** index the subset. [All assets appear; counts match the files on disk minus sidecars.]
3. **XMP from LrC:** in the catalog copy, change rating, keywords, caption and GPS on a RAW, a JPEG and a HEIC; let LrC write the metadata; rescan. [Changes appear in Immich; the asset keeps its ID, albums and faces.]
4. **Creator keyword:** assign `Creator|<name>` keywords from the IPTC creator field in the catalog copy; rescan. [Tags appear in Immich and can be searched.]
5. **RAW rendering:** compare Immich's rendering of unedited and edited `.NEF`/`.ARW` with and without "Prefer embedded preview", against LrC. [Unedited RAWs acceptable without a rendition; edited ones need one, as expected.]
6. **RAW renditions:** publish renditions for the edited RAWs into the rendition tree with an LrC publish service; index the tree as a second read-only external library; stack each rendition with its RAW; change an edit in LrC and check the rendition follows. [One visible stack per photo; the rendition carries the RAW's metadata; the folder layout is kept, or a fallback match works; a re-published edit replaces the rendition and Immich keeps it as the same asset or re-stacks it.]
7. **Collections to albums:** create albums for two LrC collections by matching their file paths to Immich assets. [Album contents match the collections; no copies uploaded.]
8. **Move in LrC:** move one folder in LrC; rescan. [Confirms the documented loss of Immich-only metadata, so rule 3 is justified.]
9. **Phone upload and sharing:** upload from two accounts with storage labels; partner sharing in both directions. [Folder layout as designed; Live Photos complete; what the partner can and cannot see is recorded.]
10. **Deletes:** delete a file in LrC and rescan; trash and empty the trash for an external and an uploaded asset in Immich. [External asset goes to trash on rescan, or reappears after an Immich delete, as documented; the uploaded original is deleted and can be restored from a ZFS snapshot or borgbackup.]
11. **Sizing input:** record thumbnail and transcode size per asset and processing time, for [#2147](https://github.com/isejalabs/homelab/issues/2147).

## Consequences

- `fiona` needs, per environment, a writable dataset for the upload library and its cache and read-only exports of the LrC library and the rendition tree (the rendition tree is regenerable from LrC, so its backup is optional); the upload dataset holds originals and must be in the borgbackup on-site and off-site sets like the LrC library, the cache dataset need not be ([#2144](https://github.com/isejalabs/homelab/issues/2144)).
- The Immich database is the only place where albums, faces and shares exist, for both kinds of media. Losing it does not lose photos but does lose that organisation, which is why the database backup and restore drill ([#2145](https://github.com/isejalabs/homelab/issues/2145)) come before any real import.
- Lightroom Mobile is replaced for uploads ([#2150](https://github.com/isejalabs/homelab/issues/2150)); the Adobe Cloud download step for phone media goes away, and LrC stops receiving phone media.
- The existing library is indexed, not imported: the full "import" in [#2151](https://github.com/isejalabs/homelab/issues/2151) is a scan of the two read-only external libraries (originals and renditions), plus three one-off jobs: creator keywords in LrC, collections to albums, renditions for edited RAWs.
- A later move to option 3 stays possible: the external library can be imported into the upload library in batches once LrC is no longer used for camera media.
