# Debugging notes — Galaxy A55

## Setup
- Device: Samsung Galaxy A55
- Build: debug APK

---

## Sessions

### 2026-04-10
1. Home screen
    a. Create new Mapp works
    b. Create new lokal works
    c. Create new lista doesn't work: Locale dfata has not been initialized, call +initializeDateFormatting(<localeZ). See also: https://docs.flutter.dev/testing(errors)>) (RESOLVED)
    d. When pressing the three dots for a mapp, a lokal or a lista, it should be an option to move it to another dir, so lista to lokal, lokal to mapp, and mapp could be in another mapp (RESOLVED)
        i.Pressing down on a list, lokal, or mapp should detatch it from its place and the user should be able to move it into another lokal/mapp. obviously not into a lista, since that is the lowest in the hiarchy (RESOLVED)
    e. Listor should be able to be duplicated into new lists. If sorted under a lokal, the same geolocation should be set for the list. The same species recorded last time (RESOLVED — "Använd som mall" on session, or "Använd tidigare lista som mall" when creating new session under a lokal)
    f. Lös lista should be renamed to just Lista, both in the home page and in (+)>Ny Mapp Ny Lokal Lös lista (should change to Ny lista) (RESOLVED)

2. When adding birds to the list
    a. First letter in each swedish bird name should be capitalized. Just the first word, e.g. "vitkindad gås" (current) changed to "Vitkindad gås" (RESOLVED)
    b. "BD" reffering to the birds directive should be in swedish, so "FD" for Fågeldirektivet (bilaga 1) (RESOLVED)
    c. When inside a list, there should be some kind of way of marking the list as finished. Start time should be the start, and end time as finished. Start times are set upon creating the list, but should be able to edit afterwards as well. One can create a list before going out, and want to specify start and stop times later. This should then be the timestamps exported as csv. (RESOLVED — stop button sets end time; tapping title allows editing start date, start time, end date and end time)
    d. when tapping on the bird name, options should appear for changing species or deleting the record in case of choosing the wrong specise (RESOLVED — tap shows "Lägg till aktivitet" and "Ta bort från lista")
    e. Also, during tap, one activity should also be able to be chosen. Activities can be provided from a list, I can get it for you. (RESOLVED)
    f. Since different birds of the same species can do different activites, there should be an option to add the same species for two records. So one can count e.g. Koltrast as both "spel/sång" and another record counting Koltrast that are "födosökande". Upon choosing two different activites, these appear as sub-rows to "koltrast". The main koltrast row shows the total sum of all recorded koltrast. (RESOLVED)
        i. Adding a bird from search now defaults to count 0. User taps + to count without activity, or taps the name to add an activity sub-row. (RESOLVED)
    g. The text promt for adding a bird is currently "Sök eller bläddra nedanför för att lägga till arter. It should be "Klicka på plustecknet för att söka eller lägga till arter". (RESOLVED — changed to "Tryck på + för att söka och lägga till arter")
    h. I think that it would be good to display "LC" for LC birds as well. (RESOLVED)
    i. Having a legend right beneath the checkboxes for "Underarter Komplex Hybrider" with information about the different info boxes would be great, so LC, NT, VU, EN, CR, RE, DD, NE, NA = Rödlistekategorier, FD1 = Med i fågeldirektivets bilaga 1, Skog = Prioriterade fågelarter i skogsvårdslagen (RESOLVED)

3. Exporting.
    a. The exporting doesn't really work yet: (RESOLVED)
    Artnamn: works
    Antal: works
    Lokalnamn: Lists wrong value - lists the list name, not the Lokal name (RESOLVED)
    No Geodata is currently in the export - this need to be implemented. (RESOLVED — GPS on lokaler, inherits to sessions, exported as SWEREF99 or WGS84 per settings)
    Slutdatum: Not yet existing (RESOLVED)
    Sluttid: Not yet existing (RESOLVED)
    b. The exported file should be exported as .csv, not as plain text (RESOLVED)
    c. There could be an option for exporting as "urklipp". That should exclude the header row and just take the content with it (this is useful for Artoportalens import function) (RESOLVED)
    d. The field "Huvudlokal" in the exported csv should be the name of the parent folder of the current lokal. If a lista isn't under a lokal, no lokal value should be given to the lista. (REMOVED — too complex, not implementing)

        
# Wish list (not yet implemented)

## W4 — Bulk export och backup (RESOLVED)
A per lokal and mapp export function - export all results as csv, preferable as a .zip-files with the folder tree intact. If not possible to export as a folder tree, the the naming of the files should follow the scheme "DateOfExport_MappName_LokalName_ListName.csv". If possible to export with folders, the export zip should be named "DateOfExport_MappName".
There should also be an option in the main menu settings for a complete export - a backup of sorts - called "Backup - exportera all data", with the name of the .zip file being "DateOfBackup_BirdTally_Backup"

## W2 — Ålder-Stadium and Kön as sub-row options (RESOLVED)

---

## W3 — Individuella start- och sluttider per rad

A per-session toggle: **"Använd global start- och sluttid"** (default) vs **"Använd individuella start- och sluttid"**.

**Global mode (default):** all rows use the session-level start/end times — current behaviour.

**Individual mode:**
- Each main observation row and each sub-row (activity/stage/gender) gets its own `start_time`, automatically set to the moment the first +1 is recorded on that row.
- `end_time` per row defaults to the session-level end time if not individually set.
- Both can be overridden manually by tapping the row.
- Exported per row in the `Startdatum / Starttid / Slutdatum / Sluttid` columns.

**Implementation scope:**
- DB migration v8: add `use_individual_times` to `sessions`; add `start_time`/`end_time` to `observations` and `activity_observations`.
- `Session` model: new field `useIndividualTimes`.
- `Observation` + `ActivityObservation` models: new `startTime`/`endTime` fields (nullable).
- `TallyProvider.increment` / `_adjustActivity`: set `startTime = now` on first +1 (when count goes from 0 → 1).
- Tally screen: toggle setting (gear icon or session options); per-row time display and tap-to-edit in individual mode.
- Export service: use per-row times when individual mode is on, fall back to session times when null.

---

## W1 — Per-observation custom GPS coordinates
Each activity sub-row should optionally have its own SWEREF 99 TM coordinate (point + radius), overriding the session-level location in the CSV export.

**Scenario:** Multiple Koltrast recorded with various activities. One individual singing at a specific spot gets a custom coordinate pinned to its "spel/sång" sub-row. A second singing individual at a different location also gets its own coordinate. Both appear as separate rows in the export CSV with their respective coordinates.

**Complexity notes:**
- Same species + same activity can have multiple records if locations differ → activity sub-rows may need to be duplicatable per location
- Custom coordinate UI: probably a tap-and-hold or edit button on the activity sub-row
- Export: each activity sub-row with a custom coordinate exports as its own CSV row (Ost/Nord/Noggrannhet overridden); rows without custom coordinates use session-level location as today
- all individual coordinates records should have the "nogrannhet" at 10 m regardless of the precision of the in-phone gps

---

## Known bugs

### B1 — Folder tree desyncs after move operations
Moving sites or folders causes them to temporarily disappear from the tree. They reappear after a full app reload. The folder tree reload is also noticeably slow. Likely a local state invalidation issue — the affected parent node is not being reloaded after a move.

### B2 — Title row and date too close vertically
In the session list (and possibly the tally screen header), the session title and its date subtitle are spaced too tightly, making it easy to mis-tap.

---

## UX wish list

### UX1 — Explain Mapp / Lokal / Besök in the + sheet
When the user taps + on the home screen, the bottom sheet currently just shows three options. Add a short explanatory subtitle to each: what a Mapp is, what a Lokal is, and what a Besök is, so new users understand the hierarchy at a glance.

> **Claudes textförslag (ej beslutat):**
> - **Ny mapp** — *"Samla flera lokaler, t.ex. ett område eller ett län."*
> - **Ny lokal** — *"En plats du återbesöker. Sparar GPS och underlättar mall för nya besök."*
> - **Nytt besök** — *"En räkning vid en viss tid. Kan ligga fritt eller under en lokal."*
>
> Kortare alternativ om utrymmet är trångt:
> - *"Grupp för flera lokaler"*
> - *"Plats med GPS som du återbesöker"*
> - *"En räkning vid ett tillfälle"*

### UX2 — Explain activity / gender / age sub-rows
When adding activity, gender or age/stage, show an explanation of the sub-row concept — that each sub-row represents additional individuals, not a property of the main count. This could be a tooltip, a one-time info dialog, or inline hint text.

> **Claudes textförslag (ej beslutat):**
>
> Kort infotext överst i bottensheeten "Lägg till underrad":
> > *"Varje underrad räknas som minst en egen individ med valda egenskaper. Huvudraden visar totalsumman."*
>
> Längre version i en `?`-dialog (AlertDialog):
> > **Om underrader**
> >
> > En underrad är en grupp individer av samma art med en gemensam egenskap — t.ex. en aktivitet, ett kön eller ett ålderstadium.
> >
> > Antalet på underraden räknas in i artens totalsumma. Vill du registrera samma art med olika beteenden lägger du till en underrad per beteende.
> >
> > *Exempel:* 3 koltrastar som sjunger + 2 som födosöker = två underrader, totalt 5 koltrastar.

### UX3 — Each sub-row is at least one individual
Make it visually clearer that every sub-row represents at least one individual, and that the parent row total includes all sub-rows plus any count registered without attributes.

> **Claudes förslag (ej beslutat) — tre kompletterande varianter:**
>
> **a) Snackbar första gången en underrad skapas i ett besök:**
> > *"Underraden räknas som 1 individ. Tryck + för fler."*
>
> **b) Sätt antalet automatiskt till 1** när en underrad skapas (istället för 0). Mer ärlig mot vad användaren just sagt: "jag såg en koltrast som sjöng". Då slipper man förklara — handlingen säger det.
>
> **c) Inline gråtext** under etiketten på underrader med count = 0:
> > *"Tryck + för att räkna"*

### UX4 — Warn that separate activity + gender + age = 3 individuals
If a user adds activity, gender, and age as separate sub-rows rather than on a single combined row, it implies three separate individuals. Show a clear hint or warning about this — ideally near the sub-row area or as part of the UX2 explanation above.

> **Claudes textförslag (ej beslutat):**
>
> Aktiv variant — SnackBar med åtgärd när användaren lägger till en *andra* attributtyp som separat underrad:
> > *"Två underrader = två individer. Vill du istället kombinera dem på en rad?"*
> > **[Kombinera]**  **[Behåll separat]**
>
> Längre förklaring i `?`-dialogen från UX2:
> > **Separata vs kombinerade underrader**
> >
> > Aktivitet, kön och ålder kan antingen läggas på samma underrad (= en individ med flera egenskaper) eller som separata underrader (= flera individer).
> >
> > *Exempel:* En sjungande hane räknas som **en** underrad med både "spel/sång" och "hane". Lägger du dem på två underrader räknas de som **två** koltrastar.
>
> Passiv variant — liten gul **(!)**-ikon vid underraden om det redan finns en annan separat underrad utan attribut, med tooltip:
> > *"Denna räknas som en egen individ utöver de andra underraderna."*

### UX5 — Sub-row label truncation
Long activity/stage/gender labels on sub-rows are clipped and not fully readable. Options: expand the row on tap, or animate the label text so it scrolls past periodically (marquee style).

> **Claudes förslag (ej beslutat):**
>
> Mer en interaktion än text, men:
> - **Förstahandsval: tap-to-expand.** Vid tap växer raden vertikalt och visar hela etiketten på två rader. Tap igen kollapsar.
> - **Andrahandsval: marquee endast vid tap-and-hold.** Mindre rörelse i UI, mindre distraherande än kontinuerlig animation.
>
> Onboarding-snackbar första gången en trunkerad underrad visas:
> > *"Tryck och håll för att se hela texten"*

### UX6 — Long-press på +/− för bulk-räkning
Långtryck på + (eller −) ökar/minskar med 5 eller 10 åt gången, med haptisk feedback. Snabbare när man räknar stora flockar (t.ex. 80 grågäss på en åker) — slipper trycka 80 gånger.

### UX7 — Större träffyta på +-knappen
+ används betydligt oftare än − under ett besök. Gör +-knappen större/mer prominent än −, så det blir lättare att träffa rätt med kalla fingrar eller vantar i fält.

### UX8 — Visa kontext på lokaler i hemskärmen
Vid varje lokal i trädet, visa en liten informationsrad: t.ex. "Senast besökt 8 apr · 14 arter totalt". Hjälper när man har många lokaler att snabbt orientera sig.

### UX9 — Risk för misstryck mellan × och − på underrad
På aktivitets-/stadie-/könsraderna ligger × (ta bort underrad) direkt bredvid − (minska antal). Lätt att råka radera hela underraden istället för att minska räknaren. Flytta × längre bort, sätt den bakom långtryck, eller kräv bekräftelse.

### UX10 — Inställning för att stänga av hjälptexter
Lägg till en toggle under kugghjulet på hemskärmen: **"Visa hjälptexter — av/på"** (default: på). När den är av döljs alla onboarding-texter och påminnelser:
- Underrubrikerna i +-arket (UX1)
- Infotexten + ?-knappen i "Lägg till underrad" (UX2)
- Snackbarsen om "Underraden räknas som 1 individ" (UX3a)
- Gråtexten "Tryck + för att räkna" på tomma underrader (UX3c)
- Eventuell varning om separata underrader (UX4)

Persisteras via `SharedPreferences` / `AppSettings`. Användbart för vana användare som vill ha ett rent UI utan instruktioner.

---

## Feature wish list

### F1 — Clear sub-rows when saving a session as a template
When a besök is saved as a template, activity/gender/stage sub-rows should be stripped. The template should only carry the pinned species list with counts reset to 0, not the detailed sub-row structure from the source session.

---

# Activities below:
1	bo, ägg/ungar
2	bo, hörda ungar
3	misslyckad häckning
4	ruvande
5	äggskal
6	föda åt ungar
7	bär exkrementsäck
8	besöker bebott bo
9	pulli/nyligen flygga ungar
10	nyligen använt bo
11	avledningsbeteende
12	bobygge
13	ruvfläckar
14	upprörd
15	varnande
16	bobesök?
17	parning/parningsceremonier
18	permanent revir
19	par i lämplig häckbiotop
20	spel/sång
21	par i lämplig häckbiotop
22	obs i häcktid, lämplig biotop
23	rastande
24	stationär
25	förbiflygande
26	födosökande
27	lockläte
28	övriga läten
29	övernattning
30	revir, ej häckning
31	ringmärktes
32	individmärkt
33	sträckförsök
34	sträckande
35	sträckande N
36	sträckande NO
37	sträckande O
38	sträckande SO
39	sträckande S
40	sträckande SV
41	sträckande V
42	sträckande NV
43	död, krockat med kraftledning
44	död, krockat med vindkraftverk
45	död, krockat med fönster
46	död, krockat med fyr
47	trafikdödad
48	död, krockat med flygplan
49	död, krockat med staket
50	dödad av elektricitet
51	drunknad i fiskenät
52	dödad av predator
53	död av sjukdom/svält
54	funnen död
55	färska spår
56	äldre spår
57	färsk spillning
58	äldre spillning
59	gammalt bo
