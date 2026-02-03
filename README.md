# Yelp – Analiza sentymentu recenzji

## Opis projektu

Projekt dotyczy **analizy sentymentu recenzji tekstowych z platformy Yelp** oraz zbadania ich zgodności z **ocenami gwiazdkowymi (1–5)** nadawanymi przez użytkowników.
Analiza została wykonana w języku **R** i ma charakter **eksploracyjny**.

W projekcie wykorzystano:

* publiczny zbiór danych **Yelp Open Dataset**,
* model NLP do analizy sentymentu udostępniony przez **Hugging Face**,
* dostęp do modelu poprzez **Hugging Face Inference API**.

Repozytorium zawiera:

* raport analityczny w formacie **R Markdown (.Rmd)**,
* aplikację **Shiny** umożliwiającą interaktywną eksplorację wyników,
* kod źródłowy odpowiedzialny za przetwarzanie danych i komunikację z API.

---

## Problem badawczy

Czy sentyment wyrażony w treści recenzji tekstowej jest zgodny z oceną gwiazdkową nadaną przez użytkownika?

---

## Hipotezy badawcze

* wraz ze wzrostem liczby gwiazdek rośnie udział recenzji o sentymencie pozytywnym,
* wraz ze spadkiem liczby gwiazdek rośnie udział recenzji o sentymencie negatywnym,
* recenzje 3-gwiazdkowe charakteryzują się największym udziałem sentymentu neutralnego (opinie mieszane).

---

## Dane

W analizie wykorzystano **Yelp Open Dataset**, obejmujący:

* recenzje użytkowników (treść tekstowa, liczba gwiazdek),
* metadane biznesów (kategorie, lokalizacja, średnia ocena).

Ze względu na ograniczenia czasowe oraz koszty API, badanie jest przeprowadzone na losowo wybranej próbie danych.

---

## Metodologia

1. Wczytanie danych Yelp w formacie JSONL.
2. Wstępne przetwarzanie danych (selekcja kolumn, eksploracja).
3. Losowy dobór próby recenzji do analizy sentymentu.
4. Obliczenie sentymentu treści recenzji przy użyciu modelu NLP (Hugging Face).
5. Przypisanie etykiet sentymentu: `NEGATIVE`, `NEUTRAL`, `POSITIVE`.
6. Analiza zależności pomiędzy sentymentem a oceną gwiazdkową.
7. Wizualizacja wyników w postaci wykresów i tabel.

---

## Model NLP

Do analizy sentymentu wykorzystano model:

```
cardiffnlp/twitter-roberta-base-sentiment-latest
```
---

## Struktura repozytorium

```
.
├── data/                                     <-- entry point danych z YELP
│   ├── yelp_academic_dataset_review.json
│   └── yelp_academic_dataset_business.json
├── analysis.Rmd                               <-- kod źródłowy
├── analysis.html                              <-- wynik mojej analizy
├── analysis_yelp/
│   └── app.R                                  <-- aplikacja shiny
├── README.md
```

---

## Konfiguracja

W pliku `.Rmd` należy ustawić ścieżki do danych oraz token API:

```r
REVIEW_PATH   <- "data/yelp_academic_dataset_review.json"
BUSINESS_PATH <- "data/yelp_academic_dataset_business.json"

HF_TOKEN <- "HF_TOKEN"
```

W aplikacji shiny po uruchomieniu należy podać odpowiednie ścieżki wejściowe dla danych oraz token HF w odpowiednim polu.
---

## Wyniki i wnioski

Analiza wykazała:

* silną zależność pomiędzy oceną gwiazdkową a sentymentem treści recenzji,
* dominację sentymentu pozytywnego dla recenzji wysoko ocenianych,
* większe zróżnicowanie sentymentu w recenzjach o ocenach pośrednich (szczególnie 3 gwiazdki).

Wyniki potwierdzają, że analiza sentymentu może stanowić użyteczne uzupełnienie oceny liczbowej, dostarczając dodatkowego kontekstu interpretacyjnego.

> Ze względu na losowy dobór próby oraz ograniczoną liczbę analizowanych recenzji, wnioski mają charakter eksploracyjny. 

---
