function(input, output, session) {
  # Make sure the reference and test treatment dropdowns don't let you select
  # the same drug
  observeEvent(input$reference_treat, {
    if (using_custom_file()) return()
    updateSelectInput(
      session, "test_treat",
      choices = c("", setdiff(ref_drug_list, input$reference_treat)),
      selected = input$test_treat
    )
  })
  observeEvent(input$test_treat, {
    if (using_custom_file()) return()
    updateSelectInput(
      session, "reference_treat",
      choices = c("", setdiff(ref_drug_list, input$test_treat)),
      selected = input$reference_treat
    )
  })

  # Create the main plot
  output$tpp_boxplot <- renderPlot({
    # abort if no treatments are chosen
    if (input$reference_treat == "" || input$test_treat == "") {
      return()
    }

    # abort if the user wants to upload a file but hasn't uploaded one yet
    if (!validate_data_input()) {
      return()
    }
    
    ref_data <- ttp_data
    
    # If using a custom TTP file, ensure the last bin category is the same
    # for both datasets
    if (using_custom_file()) {
      test_data <- custom_data()
      levels(ref_data$WEEK_BIN)[nlevels(ref_data$WEEK_BIN)] <-
        levels(custom_data()$WEEK_BIN)[nlevels(custom_data()$WEEK_BIN)]
      
      # abort if the selected test treatment doesn't exist in the data (this can
      # happen if this function is called too fast because the dropdown updates)
      if (!input$test_treat %in% unique(custom_data()$TRTDOSE)) {
        return()
      }
    } else {
      test_data <- ref_data

      # abort if the selected test treatment doesn't exist in the data (this can
      # happen if this function is called too fast because the dropdown updates)
      if (!input$test_treat %in% unique(ref_data$TRTDOSE)) {
        return()
      }
    }

    # Get data only for the two chosen drugs, and make sure the reference
    # comes before the treatment so that in the box plot it'll be on the left
    # (it will happen because "R" comes before "T")
    ref_rows <- subset(ref_data, TRTDOSE == input$reference_treat)
    ref_rows <- ref_rows[, c("WEEK_BIN", "TTP", "TRTDOSE")]
    ref_rows$TRTDOSE_NAME <- paste0("Reference: ", input$reference_treat)
    test_rows <- subset(test_data, TRTDOSE == input$test_treat)
    test_rows <- test_rows[, c("WEEK_BIN", "TTP", "TRTDOSE")]
    test_rows$TRTDOSE_NAME <- paste0("Test: ", input$test_treat)
    data <- rbind(ref_rows, test_rows)
    
    # And finally - plot!

    plot <- ggplot(data, aes(WEEK_BIN, TTP)) +
      aes(color = TRTDOSE, group = TRTDOSE) + 
      geom_point(alpha = 0.5, shape = 16, size = 1) +
      geom_boxplot(aes(group = NULL), varwidth = FALSE,
                   notch = FALSE, show.legend = TRUE) + 
      stat_summary(fun.y = median, geom = "line") +
      xlab("Time (Weeks)") +
      ylab("TTP (Days)") +
      theme_bw(base_size = 16) +
      theme(legend.position = "bottom",
            legend.box = "vertical", legend.direction = "horizontal",
            axis.text.x = ggplot2::element_text(angle = 90,
                                                hjust = 1, vjust = 0.5),
            legend.title = element_blank())
    
    # Customize the plot based on user options
    if (!input$opt_overlay) {
      plot <- plot +
        facet_grid(. ~ TRTDOSE_NAME)
    }
    if (input$opt_samplesize) {
      give.n <- function(x){
        return(c(y = min(x)*1.05,  label = length(x))) 
      }
      plot <- plot +
        stat_summary(fun.data = give.n,
                     aes(group = NULL), geom = "label", alpha = 0.1,
                     fun.y = median, fontface = "bold", fill = "white",
                     show.legend = FALSE, size = 6,
                     position = position_dodge(width = 0.8))
    }
    if (input$opt_median) {
      median.n <- function(x){
        return(c(y = ifelse(median(x) < 0,median(x),median(x)),
                 label = round(median(x),1))) 
      }
      plot <- plot + 
        stat_summary(fun.data = median.n,
                     aes(group = NULL), geom = "label", alpha = 0.1,
                     fun.y = median, fontface = "bold", fill = "white",
                     show.legend = FALSE, size = 6,
                     position = position_dodge(width = 0.8))
    }
    
    plot
  })
  
  # Read the custom TTP data file
  custom_data <- reactive({
    if (is.null(input$custom_file)) {
      return()
    }
    
    shinyjs::hide("upload_error")
    
    data <- try(read.csv(
      input$custom_file$datapath,
      na.strings = c("", " ", ".", "NA", "na"),
      stringsAsFactors = FALSE
    ), silent = TRUE)
    if (inherits(data, "try-error")) {
      shinyjs::html("upload_error", "Could not read the file")
      shinyjs::show("upload_error")
      return()
    }
    
    validate_res <- validate_dataset(data)
    if (!isTRUE(validate_res)) {
      shinyjs::html("upload_error",
        paste0("There is a problem with the file: ", validate_res))
      shinyjs::show("upload_error")
      return()
    }
    data <- clean_dataset_weeks(data)
    data
  })

  # Whether or not the user uploaded a custom TTP file for test treatment
  using_custom_file <- reactive({
    input$upload_custom == TRUE &&
      !is.null(input$custom_file) &&
      !is.null(custom_data())
  })

  # When a custom file is uploaded, change the available drug dropdowns 
  observeEvent(using_custom_file(), {
    if (!using_custom_file()) {
      updateSelectInput(
        session, "reference_treat",
        choices = c("", setdiff(ref_drug_list, input$test_treat)),
        selected = input$reference_treat)
      updateSelectInput(
        session, "test_treat",
        choices = c("", setdiff(ref_drug_list, input$reference_treat)),
        selected = input$test_treat)
      return()
    } else {
      updateSelectInput(
        session, "reference_treat",
        choices = c("", ref_drug_list),
        selected = input$reference_treat)
      
      test_drugs <- as.character(unique(custom_data()$TRTDOSE))
      updateSelectInput(
        session, "test_treat",
        choices = c("", test_drugs),
        selected = input$test_treat)
    }
  })
  
  # Determine if there is a valid dataset for the test treatment
  validate_data_input <- reactive({
    !input$upload_custom || !is.null(custom_data())
  })
  
  # Don't show the test treatment dropdown if no valid file is uploaded
  observe({
    shinyjs::toggle(id = "test_treat", condition = validate_data_input())
  })
}