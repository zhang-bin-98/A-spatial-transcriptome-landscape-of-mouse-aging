
GetAllCoordinates <- function(.data) {
    .data@images %>%
        names() %>%
        unique() %>%
        map_dfr(~{
            GetTissueCoordinates(
                    .data,
                    image = .x,
                    cols = c("row", "col"),
                    scale = NULL
                ) %>%
            rownames_to_column(var = "cellid")
        })
}

# ################################################################
#
# range marker
#
# ################################################################

single_marker <- function(df, intra_df, spot_type, dist_method, FUN, zero_check = FALSE) {

    if (length(intra_df) != 0) {

        all_df <- df %>%
            column_to_rownames("cellid") %>%
            select(row, col)

        mat <- proxy::dist(all_df, intra_df, method = dist_method) %>%
            as.matrix()

        spot_dist <- tibble(cellid = names(mat))
        spot_dist[[as_label(spot_type)]] <- mat

        if (!is.na(FUN)) {
            spot_dist <- spot_dist %>%
                mutate(!!spot_type := FUN(!!spot_type))
        }

        res <- df %>%
            left_join(spot_dist)

    } else {

        res <- df %>%
            mutate(!!spot_type := Inf)
    }

    res %>%
        select(-c(row, col))
}

#' niche marker
#' 
#' @description 标记niche周围的梯度
#' 
#' @import Seurat
#' @import tidyverse
#' @import future
#' @import future.apply
#' 
#' @param marker
#' @param spot_type 
#' @param dist_method 距离计量方法, 默认 "Euclidean"。list of all available measures can be obtained using pr_DB 
#' @param FUN 距离调整函数(NULL, ceiling) 默认 NA
#' @param n_work 线程数
#' 
NicheMarker <- function(.data, marker, spot_type, slide = orig.ident, dist_method = "Euclidean", FUN = NA, n_work = 3) {
    marker = enquo(marker)
    spot_type = enquo(spot_type)
    slide = enquo(slide)

    library(future)
    library(future.apply)

    plan(multisession, workers=n_work)
    options(future.globals.maxSize= Inf)
    message(">> how many cores can use now: ", nbrOfWorkers())

    .data@meta.data <-
        .data@meta.data %>%
        rownames_to_column(var = "cellid") %>%
         # get Coordinates
        left_join(
            GetAllCoordinates(.data)
        ) %>%
        # NM
        group_by(!!slide) %>%
        group_split() %>%
        future_lapply(function(df) {
            print(df[[as_label(slide)]][1])
            
            intra_df <- df %>%
                filter(!!marker) %>%
                column_to_rownames("cellid") %>%
                select(row, col)

            single_marker(df, intra_df, spot_type = spot_type, dist_method = dist_method, FUN = FUN)
        }, future.chunk.size = Inf) %>%
        bind_rows() %>%
        column_to_rownames(var = "cellid")

    .data@meta.data <- .data@meta.data[colnames(.data),]

    return(.data)
}
