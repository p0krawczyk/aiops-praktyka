# Lab 06b – notatki: skan zależności Trivy

## Liczba podatności
- Bez filtra (`trivy fs --scanners vuln app/`): **8** (7 w `orders-api/uv.lock`, 1 w `payments/go.mod`)
  - uv.lock: 3 HIGH, 3 MEDIUM, 1 LOW; go.mod: 1 UNKNOWN
- Po filtrze (`--severity HIGH,CRITICAL --ignore-unfixed`): **3** (same HIGH, 0 CRITICAL)

## Pliki ze znaleziskami
- `app/orders-api/uv.lock` – wszystkie 3 po filtrze; pakiet `starlette 0.41.3`
  - CVE-2025-62727 (fix 0.49.1), CVE-2026-48818 (fix 1.1.0), CVE-2026-54283 (fix 1.3.1)
- `app/payments/go.mod` – `golang.org/x/sys v0.22.0`, CVE-2026-39824, severity UNKNOWN → odpada przy filtrze HIGH/CRITICAL
- Czyste (0): `loadgen/requirements.txt`, `orders-api/requirements.txt`, `worker/requirements.txt`

## Dlaczego `requirements.txt` orders-api jest czysty, a `uv.lock` nie?
- `requirements.txt` zawiera tylko zależności **bezpośrednie** (`fastapi==0.115.6`, `uvicorn`, `pydantic`…). Nie ma w nim `starlette` – to zależność **tranzytywna** fastapi, więc Trivy nie ma jej jak zobaczyć (nie ma też lockfile'a z pełnym drzewem).
- `uv.lock` to pełny lockfile z całym drzewem i przypiętymi wersjami: jest tam `starlette 0.41.3` (wciągnięty przez `fastapi 0.115.6`) – i to on ma CVE.
- Wniosek: `requirements.txt` daje **fałszywe poczucie czystości**. Obraz budowany z `requirements.txt` (Dockerfile: `pip install -r requirements.txt`) i tak zainstaluje starlette z wersją wynikającą z ograniczeń fastapi, więc skan obrazu może pokazać te same podatności. Poprawka: podbić `fastapi` do wersji z nowszym starlette (i odświeżyć `uv.lock`).

---

## Weryfikacja odpowiedzi AI (`kolejka.md`)

**1. Czy ID i wersje zgadzają się z plikiem?**
Tak. Trzy wybrane CVE (CVE-2025-62727, CVE-2026-54283, CVE-2026-48710) sprawdzone w `wynik.json`: pakiet `starlette`, zainstalowana 0.41.3, wersje z poprawką 0.49.1 / 1.3.1 / 1.0.1, severity HIGH / HIGH / MEDIUM. Wszystko zgodne, nic nie zostało wymyślone.

**2. Czy AI wybrało coś niższego niż HIGH? Czy da się to obronić?**
Tak: CVE-2026-48710 jest MEDIUM, a pominięte zostało HIGH CVE-2026-48818. Uzasadnienie częściowo się broni: 48818 dotyczy ścieżek UNC na Windows, a kontener działa na Linuksie, więc w tym środowisku jest praktycznie nieosiągalne. Słabsza jest sama obrona wyboru 48710: opiera się na założeniu o kontroli nagłówka Host przez ALB, którego nie ma w pliku (tytuł mówi tylko o „obejściu ograniczeń”). To rozumowanie z kontekstu, nie fakt z danych. Poza tym fix do 1.3.1 zamyka wszystkie i tak, więc kolejność ma małe znaczenie praktyczne.

**3. Czego ten skan nie widzi w obrazie działającym na klastrze?**
`trivy fs` czyta tylko pliki zależności w repo. Nie widzi:
- pakietów systemowych obrazu bazowego (np. Debian/Alpine, openssl, libc) – CVE w warstwie OS,
- tego, co faktycznie zainstalował `pip install -r requirements.txt` w Dockerfile (zależności tranzytywne, których nie ma w `requirements.txt`, wersje mogą się różnić od `uv.lock`),
- binariów i narzędzi dodanych w obrazie (np. kompilat Go z wbudowanymi bibliotekami, nginx w `web`),
- obrazów z Helma, których nie budujemy sami (np. `postgres:17-alpine`),
- sekretów i błędnej konfiguracji zaszytych w warstwach obrazu,
- różnicy między repo a wdrożonym tagiem (obraz na klastrze może pochodzić ze starszego commita).
Do tego służy `trivy image` na obrazach z ECR.
