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
    d. The field "Huvudlokal" in the exported csv should be the name of the parent folder of the current lokal. If a lista isn't under a lokal, no lokal value should be given to the lista. (NOT YET IMPLEMENTED)

        
# Wish list (not yet implemented)

## W2 — Ålder-Stadium and Kön as sub-row options

Besides "Lägg till aktivitet", parent rows should also offer "Lägg till ålder-stadium" and "Lägg till kön". These create sub-rows just like activities do, each with their own counter.

Sub-rows themselves (activity, ålder-stadium, kön) should also allow adding ålder-stadium and kön to that specific sub-row.

**UI suggestion:** The tap options sheet should have a section header "Lägg till underrad" above the three choices (Aktivitet / Ålder-Stadium / Kön) to make clear these will create child rows.

**Ålder-Stadium values (Stage_Birds from ap2_template_sv.xls):**
ägg, pulli, adult, 1K, 1K+, 2K, 2K+, 2K-, 3K, 3K+, 3K-, 4K, 4K+, 4K-, 5K, 5K+, 5K-, 6K, 6K+, 6K-, 7K, 7K+, 7K-

**Kön values (Gender_Birds from ap2_template_sv.xls):**
Hane, Hona, Honfärgad, I par

**Export:** maps to the "Ålder-Stadium" and "Kön" columns in the Artportalen CSV.

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
