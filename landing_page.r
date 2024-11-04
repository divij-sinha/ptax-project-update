library(shiny)
library(quarto)

ui <- fluidPage(
    titlePanel("Property Tax Explainer"),
    sidebarLayout(
        sidebarPanel(
            textInput("pin_14", "Enter 14 digit PIN for your Parcel:"),
            actionButton("submit", "Submit")
        ),
        mainPanel(
            uiOutput("output_document")
        )
    )
)

server <- function(input, output) {
    observeEvent(input$submit, {
        req(input$pin_14)
        output$output_document <- renderUI({
            quarto_render(
                input = "ptaxsim_explainer_update.qmd",
                execute_params = list(pin_14 = input$pin_14)
            )
            renderUI({
                tags$iframe(src = "ptaxsim_explainer_update.html", width = "100%", height = "600px")
            })
        })
    })
}

shinyApp(ui = ui, server = server)
