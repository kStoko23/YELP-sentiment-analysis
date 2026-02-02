library(shiny)
library(jsonlite)
library(dplyr)
library(tibble)
library(ggplot2)
library(stringr)
library(purrr)
library(httr2)
library(tidyr)
library(DT)


read_yelp_jsonl <- function(path, nrows) {
  con <- file(path, open = "r", encoding = "UTF-8")
  on.exit(close(con), add = TRUE)
  
  lines <- readLines(con, n = nrows, warn = FALSE)
  if (length(lines) == 0) return(tibble())
  
  df <- jsonlite::fromJSON(paste0("[", paste(lines, collapse = ","), "]"))
  as_tibble(df)
}

hf_text_classification <- function(text, model_name, token) {
  url <- paste0("https://router.huggingface.co/hf-inference/models/", model_name)
  
  req <- request(url) |>
    req_headers(
      Authorization = paste("Bearer", token),
      `Content-Type` = "application/json"
    ) |>
    req_body_json(list(inputs = text), auto_unbox = TRUE) |>
    req_timeout(60) |>
    req_error(is_error = function(resp) FALSE)
  
  resp <- req_perform(req)
  resp_body_json(resp, simplifyVector = FALSE)
}

pick_best_label <- function(result) {
  if (is.null(result) || !is.list(result)) {
    return(list(label = NA_character_, score = NA_real_))
  }
  if (!is.null(result$error)) {
    return(list(label = NA_character_, score = NA_real_))
  }
  if (length(result) < 1 || !is.list(result[[1]])) {
    return(list(label = NA_character_, score = NA_real_))
  }
  
  classes <- result[[1]]
  classes <- Filter(function(x) !is.null(x[["label"]]) && !is.null(x[["score"]]), classes)
  if (length(classes) == 0) return(list(label = NA_character_, score = NA_real_))
  
  scores <- vapply(classes, function(x) as.numeric(x[["score"]]), numeric(1))
  best_i <- which.max(scores)
  
  list(
    label = as.character(classes[[best_i]][["label"]]),
    score = as.numeric(classes[[best_i]][["score"]])
  )
}

analyze_reviews <- function(df, limit, seed, model_name, token, progress = NULL) {
  set.seed(seed)
  n <- min(limit, nrow(df))
  if (n <= 0) return(tibble())
  
  sample_df <- df %>% slice_sample(n = n)
  results <- vector("list", n)
  
  for (i in seq_len(n)) {
    txt <- as.character(sample_df$text[i])
    txt <- substr(txt, 1, 2000) # shorted so API doesnt error out
    
    res <- hf_text_classification(txt, model_name, token)
    best <- pick_best_label(res)
    
    results[[i]] <- list(hf_label = best$label, hf_score = best$score)
    
    if (!is.null(progress)) progress$set(value = i)
  }
  
  bind_cols(sample_df, bind_rows(results))
}

ui <- fluidPage(
  titlePanel("Yelp – Analiza sentymentu"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Ścieżki danych"),
      textInput("review_path", "review.json (JSONL)", value = "../data/yelp_academic_dataset_review.json"),
      textInput("business_path", "business.json (JSONL)", value = "../data/yelp_academic_dataset_business.json"),
      
      tags$hr(),
      
      h4("Wczytanie danych"),
      numericInput("nrows", "Liczba wierszy do wczytania (NROWS)", value = 50000, min = 1000, step = 1000),
      actionButton("load_data", "Wczytaj dane", class = "btn-primary"),
      
      tags$hr(),
      
      h4("Sentyment"),
      textInput("model_name", "Model (HF)", value = "cardiffnlp/twitter-roberta-base-sentiment-latest"),
      passwordInput("hf_token", "HF Token (Bearer)", value = ""),
      numericInput("analyze_limit", "Liczba recenzji do analizy", value = 100, min = 10, step = 10),
      numericInput("seed", "Seed", value = 420, min = 1, step = 1),
      actionButton("run_sentiment", "Uruchom analizę sentymentu", class = "btn-success"),
      
    ),
    
    mainPanel(
      tabsetPanel(
        tabPanel(
          "Wprowadzenie",
          h3("Problem badawczy"),
          p("Czy sentyment w treści recenzji jest zgodny z oceną gwiazdkową (1–5)?"),
          h3("Hipoteza"),
          tags$ul(
            tags$li("wraz ze wzrostem liczby gwiazdek rośnie udział sentymentu pozytywnego,"),
            tags$li("wraz ze spadkiem liczby gwiazdek rośnie udział sentymentu negatywnego,"),
            tags$li("recenzje 3-gwiazdkowe mają relatywnie największy udział sentymentu neutralnego.")
          )
        ),
        
        tabPanel(
          "Dane",
          h3("Metryki – reviews"),
          tableOutput("reviews_metrics"),
          h3("Podgląd – reviews"),
          DTOutput("reviews_preview"),
          
          tags$hr(),
          
          h3("Metryki – business"),
          tableOutput("business_metrics"),
          h3("Podgląd – business"),
          DTOutput("business_preview")
        ),
        
        tabPanel(
          "Business – wykresy",
          h3("Rozkład ocen gwiazdkowych"),
          plotOutput("business_stars_plot", height = 380),
          
          tags$hr(),
          
          h3("Top kategorie biznesów"),
          numericInput("top_n", "Top N kategorii", value = 30, min = 5, step = 5),
          plotOutput("business_cats_plot", height = 520)
        ),
        
        tabPanel(
          "Sentyment",
          h3("Wyniki próby"),
          DTOutput("analyzed_head"),
          
          tags$hr(),
          
          h3("Sentyment vs ocena gwiazdkowa"),
          plotOutput("sentiment_vs_stars_plot", height = 420),
          
          tags$hr(),
          
          h3("Rozkład ocen gwiazdkowych w analizowanej próbie"),
          plotOutput("sample_stars_plot", height = 380),
          
          tags$hr(),
          h3("Tabela agregacji"),
          DTOutput("sentiment_pivot_table")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  
  rv <- reactiveValues(
    reviews = NULL,
    business = NULL,
    analyzed = NULL
  )
  
  observeEvent(input$load_data, {
    req(input$review_path, input$business_path)
    showNotification("Wczytuję dane…", type = "message")
    
    reviews_raw <- tryCatch(
      read_yelp_jsonl(input$review_path, input$nrows),
      error = function(e) { showNotification(paste("Błąd reviews:", e$message), type = "error"); tibble() }
    )
    business_raw <- tryCatch(
      read_yelp_jsonl(input$business_path, input$nrows),
      error = function(e) { showNotification(paste("Błąd business:", e$message), type = "error"); tibble() }
    )
    
    reviews <- reviews_raw %>%
      select(any_of(c("review_id", "user_id", "business_id", "stars", "text"))) %>%
      mutate(stars = as.numeric(stars))
    
    business <- business_raw %>%
      select(any_of(c(
        "business_id", "name", "address", "city", "state", "postal_code",
        "latitude", "longitude", "stars", "review_count", "is_open", "categories"
      ))) %>%
      mutate(stars = as.numeric(stars))
    
    rv$reviews <- reviews
    rv$business <- business
    rv$analyzed <- NULL
    
    showNotification("Dane wczytane.", type = "message")
  })
  
  output$reviews_metrics <- renderTable({
    req(rv$reviews)
    tibble(
      `Liczba recenzji` = nrow(rv$reviews),
      `Średnia ocena gwiazdkowa` = round(mean(rv$reviews$stars, na.rm = TRUE), 2),
      `Liczba unikalnych biznesów` = n_distinct(rv$reviews$business_id),
      `Liczba unikalnych recenzentów` = n_distinct(rv$reviews$user_id)
    )
  })
  
  output$business_metrics <- renderTable({
    req(rv$business)
    tibble(
      `Liczba unikalnych biznesów` = n_distinct(rv$business$business_id),
      `Średnia ocena gwiazdkowa` = round(mean(rv$business$stars, na.rm = TRUE), 2)
    )
  })
  
  output$reviews_preview <- renderDT({
    req(rv$reviews)
    x <- rv$reviews %>%
      mutate(text = str_trunc(text, width = 200)) %>%
      slice_head(n = 5)
    datatable(x, options = list(pageLength = 5, dom = "tip"), rownames = FALSE)
  })
  
  output$business_preview <- renderDT({
    req(rv$business)
    x <- rv$business %>% slice_head(n = 5)
    datatable(x, options = list(pageLength = 5, dom = "tip"), rownames = FALSE)
  })
  
  output$business_stars_plot <- renderPlot({
    req(rv$business)
    x <- rv$business %>%
      filter(!is.na(stars)) %>%
      count(stars, name = "count") %>%
      arrange(stars)
    
    ggplot(x, aes(x = stars, y = count)) +
      geom_col() +
      labs(
        title = "Rozkład ocen gwiazdkowych",
        x = "Oceny gwiazdkowe",
        y = "Liczba biznesów"
      ) +
      theme_minimal()
  })
  
  output$business_cats_plot <- renderPlot({
    req(rv$business)
    top_n <- input$top_n
    
    cats <- rv$business %>%
      filter(!is.na(categories)) %>%
      mutate(category = str_split(categories, ",\\s*")) %>%
      tidyr::unnest(category) %>%
      count(category, sort = TRUE)
    
    cats_top <- cats %>% slice_head(n = top_n)
    
    ggplot(cats_top, aes(x = reorder(category, n), y = n)) +
      geom_col() +
      coord_flip() +
      labs(
        title = paste0("Top ", top_n, " kategorii biznesów"),
        x = "Kategoria",
        y = "Liczba biznesów"
      ) +
      theme_minimal()
  })
  
  observeEvent(input$run_sentiment, {
    req(rv$reviews)
    req(input$model_name)
    req(input$analyze_limit)
    req(input$seed)
    
    analyzed <- tryCatch(
      analyze_reviews(
        df = rv$reviews,
        limit = input$analyze_limit,
        seed = input$seed,
        model_name = input$model_name,
        token = input$hf_token
      ),
      error = function(e) {
        showNotification(paste("Błąd sentymentu:", e$message), type = "error")
        tibble()
      }
    )
    
    rv$analyzed <- analyzed
    showNotification("Sentyment policzony.", type = "message")
  })
  
  output$analyzed_head <- renderDT({
    req(rv$analyzed)
    x <- rv$analyzed %>% select(any_of(c("stars", "hf_label", "hf_score", "text"))) %>%
      mutate(text = str_trunc(text, 140)) %>%
      slice_head(n = 10)
    datatable(x, options = list(pageLength = 10), rownames = FALSE)
  })
  
  output$sentiment_vs_stars_plot <- renderPlot({
    req(rv$analyzed)
    
    pivot_long <- rv$analyzed %>%
      filter(!is.na(stars), !is.na(hf_label)) %>%
      count(stars, hf_label, name = "count") %>%
      mutate(stars = as.integer(stars))
    
    ggplot(pivot_long, aes(x = factor(stars), y = count, fill = hf_label)) +
      geom_col() +
      labs(
        title = "Sentyment vs ocena gwiazdkowa",
        x = "Oceny gwiazdkowe",
        y = "Liczba recenzji",
        fill = "HF label"
      ) +
      theme_minimal()
  })
  
  output$sample_stars_plot <- renderPlot({
    req(rv$analyzed)
    
    counts <- rv$analyzed %>%
      filter(!is.na(stars)) %>%
      count(stars, name = "count") %>%
      arrange(stars)
    
    ggplot(counts, aes(x = factor(stars), y = count)) +
      geom_col() +
      labs(
        title = "Rozkład ocen gwiazdkowych w analizowanej próbie",
        x = "Oceny gwiazdkowe",
        y = "Liczba recenzji"
      ) +
      theme_minimal()
  })
  
  output$sentiment_pivot_table <- renderDT({
    req(rv$analyzed)
    
    pivot <- rv$analyzed %>%
      filter(!is.na(stars), !is.na(hf_label)) %>%
      count(stars, hf_label, name = "count") %>%
      tidyr::pivot_wider(names_from = hf_label, values_from = count, values_fill = 0) %>%
      arrange(stars)
    
    datatable(pivot, rownames = FALSE)
  })
  
}

shinyApp(ui, server)
