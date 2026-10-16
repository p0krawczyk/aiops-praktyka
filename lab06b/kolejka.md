# Kolejka napraw – 3 podatności najpierw

Źródło: `lab06b/wynik.json`. Kontekst: orders-api jest wystawione do internetu przez ALB, bez uwierzytelnienia użytkowników.

| # | ID | Pakiet | Zainstalowana | Z poprawką | Dlaczego |
|---|----|--------|---------------|------------|----------|
| 1 | CVE-2025-62727 | starlette | 0.41.3 | 0.49.1 | HIGH, DoS (łączenie nagłówków Range) osiągalny przez żądania HTTP, a API jest publiczne i nie wymaga logowania, więc atakujący nie potrzebuje żadnych uprawnień. |
| 2 | CVE-2026-54283 | starlette | 0.41.3 | 1.3.1 | HIGH, limity `request.form()` są po cichu ignorowane dla `application/x-www-form-urlencoded`, co umożliwia DoS na publicznym, nieuwierzytelnionym API. |
| 3 | CVE-2026-48710 | starlette | 0.41.3 | 1.0.1 | MEDIUM, ominięcie ograniczeń przez zniekształcony nagłówek Host; wystawienie przez ALB do internetu daje atakującemu kontrolę nad tym nagłówkiem. |

## Uwagi
- Wszystkie trzy dotyczą `starlette` w `orders-api/uv.lock`; podniesienie do 1.3.1 (najwyższa wersja z poprawką w pliku) zamyka je razem z pozostałymi znaleziskami starlette w pliku.
- Pominięte celowo:
  - CVE-2026-48818 (HIGH): tytuł dotyczy ścieżek UNC „on Windows”, a kontener nie działa na Windows.
  - CVE-2026-39824 (payments, `golang.org/x/sys`): severity UNKNOWN, dotyczy `golang.org/x/sys/windows`, a payments jest serwisem wewnętrznym.
- Ocena zasięgu opiera się wyłącznie na tytułach i severity z pliku; czy aplikacja faktycznie używa podatnych funkcji (np. formularzy, Range), trzeba sprawdzić w kodzie.
