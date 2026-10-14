Wypełniony szablon

Jesteś SRE. Środowisko: Kubernetes/EKS 1.36 (węzły v1.36.1-eks-3c9d2f1), eu-central-1, namespace kantyna, orders-api 1.0.0 (variant default), postgres:17-alpine jako StatefulSet.
Objaw: `$ARGUMENTS`
Dane: lab01b/awaria-zred.txt (get pods, logs --previous orders-api, describe pod postgres-0, get pvc, get nodes -L zone,instance-type; dane zredagowane)
Już sprawdziłem: Ingress i Service web działają, web zwraca stronę, błąd jest dopiero przy wywołaniu orders-api.
Zadanie: podaj 3 najbardziej prawdopodobne hipotezy, od najbardziej prawdopodobnej.
Ograniczenia: proponuj tylko komendy read-only. Nie proponuj jeszcze poprawki.
Jeśli brakuje danych, napisz, jakiej komendy potrzebujesz, zamiast zgadywać.
Format: tabela | hipoteza | dowód z danych powyżej | komenda weryfikująca |.

Odpowiedź

┌─────┬────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────────────────────────┐
│  #  │                                      Hipoteza                                      │                                             Dowód z danych                                             │                                Komenda weryfikująca                                │
├─────┼────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│     │ Konflikt strefy dostępności. Wolumen EBS (gp3) PV postgresa jest przypięty do      │ FailedScheduling: 3 node(s) had volume node affinity conflict (41 min, ponawiane x9). Wszystkie 3      │ kubectl get pv pvc-3e8a91c4-27d5-4b0f-9c6e-5a1f0d7b2e48 -o                         │
│ 1   │ strefy, w której nie ma już żadnego węzła. Nowa node group działa tylko w          │ węzły są w eu-central-1a. PVC jest Bound od 19 dni, czyli PV powstał przed wymianą węzłów. Wymiana     │ jsonpath='{.spec.nodeAffinity}' oraz kubectl get pv                                │
│     │ eu-central-1a. postgres-0 nie może się zaszeregować, więc baza nie działa.         │ node group poprzedza awarię.                                                                           │ pvc-3e8a91c4-27d5-4b0f-9c6e-5a1f0d7b2e48 -o jsonpath='{.metadata.labels}'          │
│     │                                                                                    │                                                                                                        │ (porównaj strefę z 1a)                                                             │
├─────┼────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│     │ Przyczyna wtórna: orders-api pada, bo nie ma bazy. To skutek hipotezy 1, nie       │ Logi: connect attempt 1/5…5/5 failed: Connection refused do kantyna-postgres (172.20.41.118), a potem  │ kubectl -n kantyna get endpoints kantyna-postgres (oczekuj pustych) oraz kubectl   │
│ 2   │ osobna usterka. Po 5 nieudanych próbach aplikacja kończy start błędem i wpada w    │ startup failed: database unavailable. Oba pody orders-api mają 0/1 CrashLoopBackOff, 11 restartów.     │ -n kantyna get pods -l app=kantyna-postgres -o wide (etykieta do potwierdzenia     │
│     │ CrashLoopBackOff, więc web dostaje 502.                                            │ Service ma IP, ale postgres-0 jest Pending, więc nie ma pod nim endpointów. Zgadza się to z web        │ przez --show-labels)                                                               │
│     │                                                                                    │ działającym i błędem dopiero przy wywołaniu orders-api.                                                │                                                                                    │
├─────┼────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────┼────────────────────────────────────────────────────────────────────────────────────┤
│     │ Brak węzłów w drugiej/trzeciej strefie po zmianie node group. Nowa node group ma   │ Brak węzłów w 1b i 1c. Wszystkie 3 węzły (m7i.large, wiek 14h) pochodzą z nowej grupy, a wszystkie IP  │ aws eks describe-nodegroup --cluster-name <klaster> --nodegroup-name <nowa-grupa>  │
│ 3   │ podsieci tylko w 1a, więc po usunięciu starych węzłów nie ma dokąd zaszeregować    │ to 10.0.1.x. Zdarzenie 0/3 nodes… Preemption is not helpful oznacza, że problemem nie są zasoby, tylko │ --query 'nodegroup.subnets' oraz aws ec2 describe-subnets --subnet-ids <id…>       │
│     │ poda z wolumenem z innej strefy. Hipoteza uzupełnia nr 1: tłumaczy, dlaczego dziś  │  dopasowanie strefy.                                                                                   │ --query 'Subnets[].[SubnetId,AvailabilityZone]'                                    │
│     │ nie ma węzła w strefie wolumenu.                                                   │                                                                                                        │                                                                                    │
└─────┴────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────────────────────────┘

Brakujące dane

- Strefa samego PV nie występuje w pliku. Hipotezy 1 i 3 są mocno wspierane, ale niepotwierdzone, dopóki nie będzie wyniku pierwszej komendy.
- Przydałby się też kubectl get pv,sc z volumeBindingMode dla gp3.
- Plik nie mówi, czy do wymiany użyto nazwy starej node group z innymi podsieciami. Odpowie na to aws eks list-nodegroups.

Hipotez 1–3 nie traktowałbym jako trzech niezależnych przyczyn. To jeden łańcuch: strefa węzłów, potem wolumen, potem Pending, potem brak bazy, potem CrashLoop, potem 502. Poprawki celowo nie proponuję, zgodnie z ograniczeniem.

Zbierz dane komendami read-only (kubectl get/describe/logs). Zredaguj sekrety przed analizą.