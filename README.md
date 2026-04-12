# BirdTally

En fågelräknarapp gjord för att generera .csv:er för rapportering till Artportalen. Vibekodad med Claude. Kan hantera lokaler, huvudlokaler, gps-positioner mm. Till för alla som vill ha en rapporteringsapp men inte vill använda Artportalens checklista av någon anledning.

## Funktioner

- **Räkning i fält** – lägg till arter via sökning, tryck + för att räkna
- **Aktiviteter, ålder-stadium och kön** – lägg till underrader per individ med aktivitet (t.ex. spel/sång), ålder-stadium (t.ex. 2K+) och kön (t.ex. Hona)
- **Lokaler med GPS** – sätt koordinater via GPS eller välj punkt på karta (OpenStreetMap)
- **Export till Artportalen** – exportera som CSV-fil redo att importera i Artportalen, eller kopiera som urklipp
- **Koordinatsystem** – välj mellan SWEREF 99 TM och WGS84 i inställningarna
- **Mappar och lokaler** – organisera dina besök i mappar och lokaler
- **Sessionsmallar** – starta nytt besök baserat på en tidigare lista, med samma arter men räknare nollställda

## Installation

Appen finns ännu inte i Google Play. För att installera:

1. Ladda ner senaste `app-release.apk` från [Releases](https://github.com/olofoko/BirdTally/releases)
2. Öppna filen på din Android-enhet
3. Godkänn installation från okänd källa om det efterfrågas

## Export till Artportalen

1. Tryck på de tre prickarna bredvid ett besök → **Exportera**
2. Välj **Exportera med rubrikrad** för en komplett CSV-fil, eller **Kopiera som urklipp** för direktimport i Artportalen
3. I Artportalen: välj Importera → välj koordinatformat (SWEREF 99 TM eller WGS84) → ladda upp filen

## Feedback och buggar

Hittar du ett fel eller har ett förslag? Öppna ett [issue](https://github.com/olofoko/BirdTally/issues) här på GitHub.
