# Was der Scanner tut

Er liest Quelldateien und prueft Regeln. Metriken wie McCabe und cloc
zaehlen dabei mit.

Zwei Absaetze, damit die Trennung sichtbar wird.

| Tabelle | bleibt |
|---|---|
| als | Text |

```mermaid
flowchart LR
    a["Quelle"]
    b{"Regel trifft?"}
    c["Befund"]
    a --> b
    b -->|"ja"| c
```
