count_genes <- function(inputFile,
                        outputFile = "output.csv",
                        column_names = "entrez,high,moderate,low,modifier,total,symbol,p_value,p_value_fdr,p_value_bonn") {

  column_names <- trimws(column_names)
  col_names_vector <- do.call(rbind, strsplit(column_names, ","))
  col_names_vector <- toupper(col_names_vector)
  
  variants_gene <-
    read.csv(file = inputFile,
             header = TRUE,
             sep = "\t")
  
  try(
  g_by_entrez_impact <- aggregate(
    variants_gene$variant_id,
    by = list(ENTREZ = variants_gene$entrez, impact = variants_gene$impact),
    FUN = length
  )
  )
  melt_entrez_impact <-
    reshape::melt(
      g_by_entrez_impact,
      id.vars = c("ENTREZ", "impact"),
      measure.vars = c("x")
    )
  
  result <- reshape::cast(melt_entrez_impact, ENTREZ ~ impact)
  
  impact_cols <- c('HIGH', 'MODERATE', 'LOW', 'MODIFIER')
  
  names(variants_gene) <- toupper(names(variants_gene))
  result <-
    merge(result,
          unique(variants_gene[, c('ENTREZ', 'SYMBOL')]),
          by.x = "ENTREZ",
          by.y = "ENTREZ")
  
  missing_cols <-
    col_names_vector[!(col_names_vector %in% names(result))]
  
  result[missing_cols] <- 0
  
  #p-value cannot be zero so modify later
  result[is.na(result)] <- 0
  
  result$TOTAL <- apply(result[, impact_cols], 1, sum)
  
  total_per_file <- sum(result[, impact_cols])
  total_high_moderate <-
    sum(result$HIGH) + sum(result$MODERATE)
  
num_digits_rounding <- 16

  result$P_VALUE <-
   round( phyper((result$HIGH + result$MODERATE) - 1,
           total_high_moderate,
           total_per_file - total_high_moderate,
           result$TOTAL,
           lower.tail = FALSE

    ) , num_digits_rounding)
 
 result$P_VALUE_FDR <- round( (p.adjust(result$P_VALUE, method = "fdr", n = length(result$P_VALUE))), num_digits_rounding)
 result$P_VALUE_BONN <- round( (p.adjust(result$P_VALUE, method = "bonferroni", n = length(result$P_VALUE))), num_digits_rounding)
   
 result <- result [, c(col_names_vector)]


  write.table(result,
              file = outputFile,
              row.names = FALSE,
              sep = "\t")
  
  
}
