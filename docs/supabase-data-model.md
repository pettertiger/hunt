# Datamodell för jaktappen

Detta dokument beskriver första versionens logiska Supabase-modell. Det är ett designunderlag, inte en körbar migration. Inbjudningslänkar och deltagarbehörighet kräver serverkontrollerade funktioner innan tabeller exponeras för deltagare.

## Grundstruktur

- `teams`: jaktlaget. Första installationen har ett jaktlag.
- `teams.admin_user_id`: den enda administratören för jaktlaget. Kolumnen är inte direkt ändringsbar av klienten.
- `team_access`: övriga inloggade jaktledare. Endast administratören får ändra medlemskapet. Administratörsbyte sker genom en transaktionell RPC; den tidigare administratören blir jaktledare.
- `people`: ordinarie deltagare i jaktlagets register, med namn och vanliga roller. Kontaktuppgifter behövs inte för kopiera-/dela-inbjudningar.
- `dogs`: jaktlagets hundregister; varje registrerad hund kan kopplas till en ägare i `people`.
- `seasons`: explicita jaktsäsonger, till exempel `2026/2027`.

Alla lagägda poster ska bära `team_id` eller nå laget via sin förälder. Databasen ska använda främmande nycklar och kontroller så att poster inte kan länkas mellan olika jaktlag.

## Marker, kartor och pass

- `marks`: jaktlagets marker. Fän är första marken.
- `mark_map_versions`: en PDF-version per uppladdning, med lagringsnyckel, versionsnummer, uppladdare och datum. PDF-originalet och en rasteriserad `.preview.png`-systerfil lagras i den privata Supabase Storage-bucketen; editorn visar förhandsbilden för snabb och tillförlitlig mobilrendering. Endast jaktledare får hantera filer; deltagarlänkar hämtar signerade länkar via serverfunktion.
- `passes`: namngivna pass som tillhör en mark och har ett stabilt ID oberoende av kartversion.
- `pass_positions`: passets relativa `x`- och `y`-position på en specifik kartversion. Koordinaterna normaliseras till intervallet `0..1`; de är inte GPS-koordinater.

Varje `hunt_mark` pekar på den `mark_map_version` som användes för jakten. Nya jakter använder markens aktuella version. Kartbyte skapar en ny version; passplaceringar granskas och läggs vid behov in på nytt. Gamla versioner och genomförda jakters kopplingar bevaras.

## Arter och jaktregler

- `species`: jaktlagets anpassningsbara artlista, med separata flaggor för observation och fällt vilt.
- `species_age_classes`: åldersklasser kopplade till en art, till exempel kid för rådjur och kalv för älg. De inaktiveras i stället för att raderas så att äldre rapporter behåller sin betydelse.
- `mark_species_rules`: en regel per kombination av säsong, mark och art. Regeltyp är `open`, `quota` eller `closed`; en fri regel kan ha en anvisning, till exempel ”jägarmässigt”.
- `mark_species_quota_categories`: manuella antal per tilldelningskategori, till exempel hjort, hind och kalv. Kön och artens åldersklass anges när det är relevant.
- `hunt_rule_snapshots` och `hunt_rule_quota_snapshots`: regler och siffror kopierade till jakten. Jaktledningen justerar kvoten manuellt; rapportering av fällt vilt räknar inte ned den automatiskt.

En `closed`-regel eller kategori med noll kvar visas som otillgänglig. Jaktledningen kan ändå rapportera ett faktiskt fällt djur som ett undantag med obligatorisk motivering. Undantaget ändrar inte den manuella kvoten.

## Jakter, deltagare och planering

- `hunts`: säsong, datum, jaktstatus, anmälningsstatus och sista svarsdag. Jaktledningen ändrar jaktstatus manuellt; inställda jakter raderas inte. Rapportstatus lagras bara på rapporten.
- `hunt_marks`: marker som ingår i jakten samt kartversionen för respektive mark.
- `hunt_participants`: en post per inbjuden person och jakt. Posten refererar antingen till `people` eller innehåller gästens namn. Gästprofilen är begränsad till jakten.
- `drives`: såtar i en jakt, med ordning och namn.
- `drive_marks`: vilka av jaktens marker som används i respektive såt.
- `drive_participants`: deltagande och passfördelning per såt. Tillstånd skiljer mellan `pending`, `no_pass` och `assigned`. Flera deltagare får dela ett pass.
- `hunt_dogs`: registrerade hundar eller tillfälliga gästhundar som deltar i jakten.
- `drive_dog_assignments`: hundens deltagande och en ansvarig förare per hund och såt. Föraren kan vara gäst eller någon annan än ägaren.

En deltagare kan vara med i en såt utan pass. Samma person ska inte kunna få motstridiga pass i samma såt; databasen eller skrivfunktionen ska avvisa eller flagga dubbel tilldelning.

## Inbjudningar och måltider

- `hunt_participants` innehåller svar: `unanswered`, `yes`, `no` eller `unsure`, en privat kommentar och en hash av den personliga inbjudningstoken. Länken kan återkallas. Efter stängd anmälan är svaret låst, men jaktinformationen och rapporten är fortsatt läsbara tills länken återkallas.
- `hunt_meals`: högst en lunch och en middag per jakt. Fält omfattar gemensam/ej gemensam, plan, tid, plats och ansvarig deltagare.
- `meal_responses`: separat ja/nej till respektive gemensam måltid och frivillig kostkommentar. Kommentaren är endast synlig för jaktledningen och ansvarig för just den måltiden.

Jaktledningen är ensam om att ändra jakt- och måltidsplanering. Måltidsansvarig får läsa måltidssvar och kommentarer men får inte redigera planen om hen inte också är jaktledare.

## Jaktrapporter

- `hunt_reports`: högst en rapport per jakt, synlig för inbjudna deltagare via deras jaktlänk.
- `harvested_animals`: en post per djur med art, valfritt kön (`male`/`female`/tomt), valfri åldersklass från artens lista, pass och skytt. Inget tidsfält behövs. Undantag har motivering och flagga.
- `search_events`: egna eftersökshändelser med utfall, till exempel återfunnet/inte återfunnet, och valfri anteckning.
- `observations`: endast vilt som setts; art, antal, valfri såt/pass och kommentar.

## Behörighet och samtidiga ändringar

- `teams.admin_user_id` och `team_access` är enda källorna till administratörs-/jaktledarbehörighet; frontendens e-postlista är inte en behörighetsgräns.
- RLS är aktiverat på alla lagtabeller. Administratörer och jaktledare får läsa och ändra jaktlagets data; endast administratören får hantera `team_access`.
- Deltagarlänkar får inte ge direkt `anon`-åtkomst till tabeller. En Edge Function eller en snävt begränsad RPC validerar token och returnerar endast jaktens läsinformation. Skrivning via länk begränsas till deltagarens eget RSVP- och måltidssvar. Token lagras endast hashad och jämförs på serversidan.
- Privata deltagar- och kostkommentarer filtreras bort för andra deltagare; jaktledning och berörd måltidsansvarig får endast den åtkomst som anges ovan.
- Delade redigerbara poster har en versionsräknare. Skrivning sker villkorat på senast lästa version. Vid konflikt avvisas den gamla skrivningen så att ändringen inte tyst skrivs över; realtidsuppdatering krävs inte.

## MVP-kontrollflöde

Skapa säsongen `2026/2027`, marken Fän, A3-kartan, passmarkörer och Fäns artregler. Skapa en jakt med två såtar, bjud in ordinarie deltagare och en gäst, samla RSVP och måltidssvar, tilldela delade pass och hundförare, stäng anmälan, och registrera efter jakten fällt vilt, eftersök och observationer. Ändra sedan Fäns manuella kvot inför nästa jakt och verifiera att den äldre jaktens regel- och kartversion är oförändrad.

Automatisk WeHunt-synk, e-post/SMS-utskick och avancerad statistik ingår inte i första versionen.
