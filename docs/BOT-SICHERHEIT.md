# GameBot absichern: Regeln für die WoW-Brücke

GuildPride schickt `[GP]`-Zeilen über Blizzards Gildenchat-Spiegelung nach
Discord. Blizzard postet jede Zeile **unter dem Discord-Konto des Spielers**,
der sie geschrieben hat. Das Problem: Jedes Gildenmitglied kann so eine Zeile
auch **von Hand in den Gildenchat tippen**, zum Beispiel
`[GP] DKP #abc123 +500 Bonus: Ich`. Das Addon kann das nicht verhindern. Der
Bot muss es prüfen.

## Regeln

1. **DKP nur von Offizieren.** Zeilen, die mit `[GP] DKP` beginnen (Buchung,
   Verfall, `zurückgenommen`/`undone`), nur annehmen, wenn der Discord-Autor
   eine Offiziersrolle hat. Die Rolle(n) im Dashboard unter *WoW-Brücke*
   einstellbar machen (Standard: keine → DKP-Zeilen werden ignoriert, bis eine
   Rolle gewählt ist).
2. **Events ändern oder löschen nur der Ersteller oder Offiziere.** Der
   Ersteller ist der WoW-Charakter, den der Autor mit `/wow link` verknüpft hat.
3. **Anmeldungen nur für sich selbst.** Eine Anmeldung für Charakter X nur
   annehmen, wenn X mit dem Discord-Autor verknüpft ist, *oder* wenn sie von
   einem verknüpften Mitglied weitergeleitet wurde (Spieler ohne Discord) –
   dann im Event mit kleinem Hinweis „weitergeleitet von …“ anzeigen.
4. **Protokoll.** Jede angenommene DKP-Zeile mit Discord-Autor (ID und Name),
   Zeit und Originaltext in einem Log-Kanal oder im Dashboard festhalten.
   Abgelehnte Zeilen ebenfalls, mit Grund.
5. **Drosseln.** Pro Autor höchstens z. B. 20 `[GP]`-Zeilen pro Minute,
   darüber ignorieren und einmal im Log-Kanal warnen.
6. **Doppelte Buchungs-IDs ignorieren.** `DKP #id` ist eindeutig; eine zweite
   Zeile mit derselben ID (außer `zurückgenommen`) nicht noch einmal buchen.

## Beispiel (discord.js)

```js
// officerRoleIds: im Dashboard gewählt, je Discord-Server gespeichert
function isOfficer(member, officerRoleIds) {
  return officerRoleIds.length > 0 &&
    member?.roles?.cache?.some(r => officerRoleIds.includes(r.id));
}

client.on('messageCreate', async (msg) => {
  if (!msg.content.startsWith('[GP] ')) return;
  const cfg = await getBridgeConfig(msg.guildId);          // dein Speicher
  if (msg.channelId !== cfg.bridgeChannelId) return;
  if (!rateOk(msg.author.id)) return logReject(msg, 'zu viele Zeilen');

  const body = msg.content.slice(5);
  if (body.startsWith('DKP')) {
    if (!isOfficer(msg.member, cfg.officerRoleIds)) {
      return logReject(msg, 'DKP nur von Offizieren');
    }
    await handleDkpLine(body, msg);                        // vorhandene Logik
    return logAccept(msg);
  }
  // Events / Anmeldungen: Ersteller bzw. Charakter gegen /wow link prüfen
  await handleEventLine(body, msg, { linkedChar: await linkedCharOf(msg.author.id) });
});
```

Sobald ich den Bot-Code habe, baue ich das direkt ein, inklusive der
Dashboard-Einstellung für die Offiziersrollen.
