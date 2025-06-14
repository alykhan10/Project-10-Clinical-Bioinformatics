# Loading the Required Libraries
library(ggbiplot)
library(stringr)
library(pheatmap)

# Loading the Required Datasets
clinical.data = read.csv("C:\\Users\\alykh\\Downloads\\Group Project\\TCGA-LUSC\\data_clinical_patient.txt", , sep = '\t', header = FALSE)
mutations.data = read.csv("C:\\Users\\alykh\\Downloads\\Group Project\\TCGA-LUSC\\data_mutations.txt", , sep = '\t', header = FALSE)
rnaSeq.data = read.csv("C:\\Users\\alykh\\Downloads\\Group Project\\TCGA-LUSC\\RNAseq_LUSC.csv")

# Renaming Columns for Clinical Dataset
colNameClinical <- clinical.data[5,]
clinical.data <-  clinical.data[c(-1,-2,-3,-4,-5),]
names(clinical.data) <- colNameClinical

# Renaming Columns for Mutation Dataset
colNameMutation <-  mutations.data[1,]
mutations.data <- mutations.data[c(-1),]
names(mutations.data) <-  colNameMutation

# Renaming the Patient IDs
mutationID <-  mutations.data$Tumor_Sample_Barcode
mutationID <- str_replace(mutationID, "-01","")
mutations.data$Tumor_Sample_Barcode <- mutationID

rnaNames <- colnames(rnaSeq.data)
rnaNameschanged <- strtrim(rnaNames, 12)
rnaNameschanged <-  str_replace_all(rnaNameschanged,"\\.","-")
names(rnaSeq.data) <- rnaNameschanged

# Getting the Common Patients in All Datasets
clinicalID <- unique(clinical.data$PATIENT_ID)
mutationID <-  unique(mutations.data$Tumor_Sample_Barcode)
rnaID <- unique(colnames(rnaSeq.data))
rnaID <- rnaID[-1]

commonPatients <- intersect(intersect(mutationID,clinicalID), rnaID)

# Extracting the Hugo Symbols and Variant Classification from Mutation Data
mutations.data <- mutations.data[mutations.data$Tumor_Sample_Barcode %in% commonPatients, ]

hugo <- as.data.frame(table(mutations.data$Hugo_Symbol))
var.class <- as.data.frame(table(mutations.data$Variant_Classification))

# Plot the Frequency of the Different Variant Classifications
ggplot(data=var.class, aes(Var1, y=Freq))+
  geom_col()+
  theme(axis.text.x = element_text(angle = 45,hjust=1))

# Plotting the Frequency of Variants Based on the Variant Class Column
var.class2 <- as.data.frame(table(mutations.data$VARIANT_CLASS))
ggplot(data=var.class2, aes(x=Var1, y=Freq))+
  geom_col(aes(fill=Var1))

# Plotting the Frequency of Variants Based on the Variant Type Column
var.type <- as.data.frame(table(mutations.data$Variant_Type))
ggplot(data=var.type, aes(x=Var1, y=Freq))+
  geom_col( aes(fill=Var1))

# Plotting the Genes Based on Highest to Lowest Frequency
hugo.ordered <- hugo[order(-hugo$Freq),]
ggplot(data=hugo.ordered[1:15,], aes(x=Var1, y=Freq))+
  geom_col()+
  theme(axis.text.x = element_text(angle = 45,hjust=1))+
  scale_x_discrete(limits = hugo.ordered[1:15,]$Var1)

# Generating an Oncoplot Matrix Based Off the Variant Classification Column
cnv_events_1 = unique(mutations.data$Variant_Classification)
oncomat_classification = reshape2::dcast(
  data = mutations.data,
  formula = Hugo_Symbol ~ Tumor_Sample_Barcode,
  fun.aggregate = function(x, cnv = cnv_events_1) {
    x = as.character(x)
    xad = x[x %in% cnv]
    xvc = x[!x %in% cnv]
    
    if (length(xvc) > 0) {
      xvc = ifelse(test = length(xvc) > 1,
                   yes = 'Multi_Hit',
                   no = xvc)
    }
    
    x = ifelse(
      test = length(xad) > 0,
      yes = paste(xad, xvc, sep = ';'),
      no = xvc
    )
    x = gsub(pattern = ';$',
             replacement = '',
             x = x)
    x = gsub(pattern = '^;',
             replacement = '',
             x = x)
    return(x)
  },
  value.var = 'Variant_Classification',
  fill = '',
  drop = FALSE
)

# Ordering the Variant Classification Oncomat Based Off Data Frequency for Missense Mutations or Otherwise
mat_classification <- oncomat.classification.ordered
mat_classification[mat_classification != "Missense_Mutation"] = 0
mat_classification[mat_classification == "Missense_Mutation"] = 1
mat_classification <- apply(mat_classification, 2 ,as.numeric)
mat_classification <- as.matrix(mat_classification)
rownames(mat_classification)  <- row.names(oncomat.classification.ordered)

# Constructing the Variant Classification Heatmap
reduce.mat.classification <- mat_classification[1:3,]
res <- pheatmap(reduce.mat.classification,
                cluster_rows = F,
                show_colnames=FALSE)
cluster_classification <-  as.data.frame(cutree(res$tree_col, k = 2))

library("survival")
library("survminer")
library("SummarizedExperiment")

# Creating a Dataframe with the Relevant Clinical Variables
clin_df <- clinical.data[c("PATIENT_ID", "DAYS_LAST_FOLLOWUP", "PATH_T_STAGE", "PFS_STATUS", "PFS_MONTHS")]

# Creating a New Boolean Variable for the Status of the Patient 
clin_df$PFS_STATUS <- as.logical(as.integer(strtrim(clin_df$PFS_STATUS, 1)))

# Adding a New Column to the Dataframe that Stores the Days to Death for the Patients
clin_df$PFS_DAYS <- as.numeric(clin_df$PFS_MONTHS) * (365/12)

# Assigning Null Values in the Days to Last Followup Column as Zero
empty.idx <- which(clin_df$DAYS_LAST_FOLLOWUP == "")
clin_df$DAYS_LAST_FOLLOWUP[empty.idx] <- 0

# Assigning the Common Patients to the Dataframe
clin_df <- clin_df[clin_df$PATIENT_ID %in% commonPatients, ]

# Adding a Cluster Variable into the Dataframe
clin_df$CLUSTER <- cluster_classification[,1] 

# Creating a Variable that Equals Days to Death for Dead and Days to Last Followup for Alive Patients
clin_df$PROGRESSION_FREE_SURVIVAL = as.numeric(ifelse(clin_df$PFS_STATUS, clin_df$PFS_DAYS, clin_df$DAYS_LAST_FOLLOWUP))

# Fitting the Survival Model with the Mutation Clusters
fit = survfit(Surv(clin_df$PROGRESSION_FREE_SURVIVAL, clin_df$PFS_STATUS) ~ CLUSTER, data = clin_df)

# Producing a Kaplan-Meier Plot from the Fitted Model
ggsurvplot(fit, data = clin_df, pval = T, risk.table = T, risk.table.col = "strata", risk.table.height = 0.35)

# Removing Any Letters at the End of the Tumor Stage
clin_df$PATH_T_STAGE <- gsub("[AB]$", "", clin_df$PATH_T_STAGE)

# Subsetting the Dataframe with Overall Survival Values that Do Not Equal Zero or NA
clin_df <- subset(clin_df, is.na(clin_df$PROGRESSION_FREE_SURVIVAL) == FALSE)
clin_df <- subset(clin_df, clin_df$PROGRESSION_FREE_SURVIVAL != 0)

# Assigning Null Values in the Tumor Stage Column as NA
empty.idx2 <- which(clin_df$PATH_T_STAGE == "")
clin_df$PATH_T_STAGE[empty.idx2] <- NA

cat("No. of Patients for Each Tumor Stage:\n")
table(clin_df$PATH_T_STAGE)

# Fitting the Survival Model with the Tumor Stage Clusters
fit = survfit(Surv(PROGRESSION_FREE_SURVIVAL, PFS_STATUS) ~ PATH_T_STAGE, data = clin_df)

# Producing a Kaplan-Meier Plot from the Fitted Model 
ggsurvplot(fit, data = clin_df, pval = T, risk.table = T, risk.table.height = 0.35)

# Assigning the Column Data as the Cluster from the Mutation Analysis
colData <- cluster_classification

# Renaming the Column Name for colData to 'Cluster Group'
colnames(colData)[which(names(colData) == "cutree(res$tree_col, k = 2)")] <- "cluster_group"

# Assigning the RNA Sequencing Data to the CountData Variable
countData <- rnaSeq.data

# Removing the First Column from CountData Matrix
rownames(countData) <- countData[, 1]

# Retaining Samples with Number of Reads Greater than One 
countData <- countData[, -1]
countData <- countData[rowSums(countData)>1,]

# Extracting Common Column Names
common_cols <- intersect(colnames(countData), rownames(colData))
common_cols <- intersect(common_cols, commonPatients)

# Subsetting CountData to Only Keep the Common Patients
countData <- countData[, common_cols]

# Display the filtered countData
head(countData)

# Reordering Rows in colData Based on the Desired Order
desired_order <- colnames(countData)
colData <- colData[desired_order, , drop = FALSE]

head(colData)

# Transposing the Matrix of Values for the Samples
sampleDists = dist(t(countData),upper = TRUE)

# Plotting the the Euclidean Distance Between Samples Using a Heatmap
annot_col = data.frame(colData$cluster_group)
row.names(annot_col) <- rownames(colData)

sampleDistMatrix = as.matrix(sampleDists)
rownames(sampleDistMatrix) = colnames(countData)
colnames(sampleDistMatrix) = colnames(countData)

pheatmap(sampleDistMatrix,
         clustering_distance_rows = sampleDists,
         clustering_distance_cols = sampleDists,
         cluster_rows=FALSE, show_rownames=TRUE,
         cluster_cols=TRUE,
         annotation_col=annot_col)

# Visualizing Sample-to-Samples Distances Using a Principle Component Analysis
pca_res <- prcomp(t(countData))
score <- pca_res$x

score = as.data.frame(score)
score$color <- as.factor(colData$cluster_group)

ggplot(score, aes(x=PC1, y=PC2,  color = color)) + 
  geom_point(size = 4)

# Normalizing the Log Count
log2 <- log(countData+1, base = 2)

# Loading the Required Library for Differential Expression Analysis
library(DESeq2)

# Performing the Differential Expression
dds <- DESeqDataSetFromMatrix(countData = countData, colData = colData, design = ~ cluster_group)

# Running the Differential Expression Pipeline
dds = DESeq(dds)

# Building the Results Table
res <- results(dds)

# Obtaining the Metadata in the Columns
mcols(res, use.names = TRUE)

# Summarizing the Results
summary(res)

# Lowering the False Discovery Rate Threshold
res.05 <- results(dds, alpha = 0.05)
table(res.05$padj < 0.05)

# Raising the Log2 Fold Change Threshold
resLFC1 <- results(dds, lfcThreshold = 0.001)
table(resLFC1$padj < 0.05)

# Ordering the Results in the Table by the Smallest P-Value
res <- res[order(res$pvalue),]
summary(res)

# Determining the Number of Adjusted P-Values Less than 0.1
sum(res$padj < 0.1, na.rm=TRUE)

# Considering All Genes with an Adjusted P-Value Below 5%
sum(res$padj < 0.05, na.rm=TRUE)

# Retrieving the Number of Significant Genes with the Strongest Down-Regulation
resSig <- subset(res, padj < 0.05)
head(resSig[order( resSig$log2FoldChange),])

# Retrieving the Number of Significant Genes with the Strongest Up-Regulation
head(resSig[order(resSig$log2FoldChange, decreasing=TRUE), ])

# Plotting the Log2 Fold Changes Over the Mean of Normalized Counts
plotMA(res, ylim=c(-2,2))

# Selecting the Subset of Genes with the Largest Positive Log2 Fold Change
genes_upregulated <- order(resSig$log2FoldChange, decreasing = TRUE)[1:10]

# Selecting the Subset of Genes with the Largest Negative Log2 Fold Change
genes_downregulated <- order(resSig$log2FoldChange, decreasing = FALSE)[1:10]

# Binding the Vectors to Select the Most Significant Genes
genes_significant <- cbind(genes_upregulated, genes_downregulated)

# Obtaining a Subset of the Names for the Top 10 Upregulated and Downregulated Genes
gene_names_upregulated <- rownames(resSig)[genes_upregulated]
gene_names_downregulated <- rownames(resSig)[genes_downregulated]

gene_names <- cbind(gene_names_upregulated, gene_names_downregulated)
gene_names

# Performing the Variance Stabilizing Transformation
vsd <- vst(dds)

# Plotting the Heatmap for the Most Significant Genes
annot_col = data.frame(colData$cluster_group)
row.names(annot_col) <- rownames(colData)

sampleMatrix <- assay(vsd)[genes_significant,]

rownames(sampleMatrix) = rownames(countData[genes_significant,])
colnames(sampleMatrix) = colnames(countData)

pheatmap(sampleMatrix , cluster_rows=FALSE, show_rownames=TRUE,
         cluster_cols=TRUE, annotation_col=annot_col)

# Loading the Required Libraries
library("AnnotationDbi")
library("org.Hs.eg.db")

# Extracting the Substring of Ensembl IDs for the Valid Keys
ensemblID <- rownames(resSig)
ensemblID <- substr(ensemblID, 1, 15)

# Performing Gene Annotation for the KEGG Pathways
resSig$symbol = mapIds(org.Hs.eg.db,
                       keys = ensemblID, 
                       column = "SYMBOL",
                       keytype = "ENSEMBL",
                       multiVals = "first")

resSig$entrez = mapIds(org.Hs.eg.db,
                       keys = ensemblID, 
                       column = "ENTREZID",
                       keytype = "ENSEMBL",
                       multiVals = "first")

resSig$name =   mapIds(org.Hs.eg.db,
                       keys = ensemblID, 
                       column = "GENENAME",
                       keytype = "ENSEMBL",
                       multiVals = "first")

head(res, 10)

# Loading the Required Libraries
library(pathview)
library(gage)
library(gageData)

# Implementing the KEGG Analysis on Signaling and Metabolic Pathways Only
data(kegg.sets.hs)
data(sigmet.idx.hs)

kegg.sets.hs = kegg.sets.hs[sigmet.idx.hs]

head(kegg.sets.hs, 3)

# Obtaining the Log2 Fold Changes Result
foldchanges = resSig$log2FoldChange
names(foldchanges) = resSig$entrez
head(foldchanges)

# Looking at the Results from the Pathway Analysis
keggresSig = gage(foldchanges, gsets = kegg.sets.hs)
attributes(keggresSig)

# Obtaining the Top 5 Upregulated and Downregulated KEGG Genes
keggres_top <- rownames(keggresSig$greater)[1:5]
keggres_bottom <- rownames(keggresSig$less)[1:5]

# Retrieving the IDs of the Top 5 Upregulated and Downregulated KEGG Genes
keggresid_top <- substr(keggres_top, start = 1, stop = 8)
keggresid_bottom <- substr(keggres_bottom, start = 1, stop = 8)

# Drawing Plots for the Top 5 Upregulated and Downregulated Pathways
pathview(gene.data = foldchanges, pathway.id = keggresid_top, species = "hsa")
pathview(gene.data = foldchanges, pathway.id = keggresid_bottom, species = "hsa")