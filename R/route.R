#' Plan routes on the transport network
#'
#' Takes origins and destinations, finds the optimal routes between them
#' and returns the result as a spatial (sf or sp) object.
#' The definition of optimal depends on the routing function used
#'
#' @inheritParams od_coords
#' @inheritParams line2route
#' @param cl Cluster
#' @family routes
#' @export
#' @examples
#' r <- overline(routes_fast_sf, "length")
#' l <- od2line(od_data_sample[2:5, 1:3], cents_sf)
#' sln <- stplanr::SpatialLinesNetwork(r)
#' # calculate shortest paths
#' plot(sln)
#' plot(l$geometry, add = TRUE)
#' sp <- stplanr::route(
#'   l = l,
#'   route_fun = stplanr::route_local,
#'   sln = sln
#' )
#' plot(sp["all"], add = TRUE, lwd = 5)
#' \donttest{
#' # these lines require API keys/osrm instances
#' from <- c(-1.5484, 53.7941) # from <- geo_code("leeds rail station")
#' to <-   c(-1.5524, 53.8038) # to <- geo_code("university of leeds")
#' r1 <- route(from, to, route_fun = cyclestreets::journey)
#' r2 <- route(from, to, route_fun = cyclestreets::journey, plan = "quietest")
#' plot(r1)
#' plot(r2)
#' r = route(cents_sf[1:3, ], cents_sf[2:4, ], route_fun = cyclestreets::journey) # sf points
#' summary(r$route_number)
#' dl <- od2line(od_data_sample[1:3, ], cents_sf)
#' route(dl, route_fun = cyclestreets::journey)
#' route(dl, route_fun = cyclestreets::journey, plan = "quietest")
#' route(dl, route_fun = cyclestreets::journey, plan = "balanced")
#' route(dl, route_fun = cyclestreets::journey, list_output = TRUE)
#' route(dl, route_fun = cyclestreets::journey, save_raw = TRUE, list_output = TRUE)
#' # with osrm backend - need to set-up osrm first - see routing vignette
#' if(require(osrm)) {
#'   message("You have osrm installed")
#'   osrm::osrmRoute(c(-1.5, 53.8), c(-1.51, 53.81))
#'   osrm::osrmRoute(c(-1.5, 53.8), c(-1.51, 53.81), , returnclass = "sf")
#'   # mapview::mapview(.Last.value) # check it's on the route network
#'   route(l = pct::wight_lines_30[1:2, ], route_fun = osrm::osrmRoute, returnclass = "sf")
#' }
#' if(require(cyclestreets)) { # with cyclestreets backend
#'   l <- pct::wight_lines_30
#'   system.time(r <- route(l, route_fun = cyclestreets::journey))
#'   plot(r)
#'   library(parallel)
#'   library(cyclestreets)
#'   cl <- makeCluster(detectCores())
#'   clusterExport(cl, c("journey"))
#'   system.time(r2 <- route(l, route_fun = cyclestreets::journey, cl = cl))
#'   plot(r2)
#'   identical(r, r2)
#'   stopCluster(cl)
#' }
#' }
route <- function(from = NULL, to = NULL, l = NULL,
                  route_fun = stplanr::route_cyclestreets,
                  n_print = 10, list_output = FALSE, cl = NULL, ...) {
  UseMethod(generic = "route")
}
#' @export
route.numeric <- function(from = NULL, to = NULL, l = NULL,
                          route_fun = stplanr::route_cyclestreets,
                          n_print = 10, list_output = FALSE, cl = NULL, ...) {
  odm <- od_coords(from, to)
  l <- od_coords2line(odm)
  route(l, route_fun = route_fun, ...)
}
#' @export
route.sf <- function(from = NULL, to = NULL, l = NULL,
                     route_fun,
                     n_print = 10, list_output = FALSE, cl = NULL, ...) {
  FUN <- match.fun(route_fun)
  # generate od coordinates
  ldf <- od_coords(from, to, l)
  # calculate line data frame
  if(is.null(l)) {
    l <- od_coords2line(ldf)
  }
  if(list_output) {
    list_out <- if (requireNamespace("pbapply", quietly = TRUE)) {
      if(is.null(cl)) {
        pbapply::pblapply(1:nrow(l), function(i) route_l(FUN, ldf, i, l, ...))
      } else {
        pbapply::pblapply(1:nrow(l), function(i) route_l(FUN, ldf, i, l, ...))
      }
    } else {
      lapply(1:nrow(l), function(i) route_l(FUN, ldf, i, l, ...))
    }
  } else {
    list_out <- if (requireNamespace("pbapply", quietly = TRUE)) {
      if(is.null(cl)) {
        pbapply::pblapply(1:nrow(l), function(i) route_i(FUN, ldf, i, l, ...))
      } else {
        pbapply::pblapply(1:nrow(l), function(i) route_i(FUN, ldf, i, l, ...), cl = cl)
      }
    } else {
      lapply(1:nrow(l), function(i) route_i(FUN, ldf, i, l, ...))
    }
  }


  list_elements_sf <- most_common_class_of_list(list_out, "sf")
  if(sum(list_elements_sf) < length(list_out)) {
    failing_routes <- which(!list_elements_sf)
    message("These routes failed: ", paste0(failing_routes, collapse = ", "))
    message("The first of which was:")
    print(list_out[[failing_routes[1]]])
  }
  if(list_output | ! any(list_elements_sf)) {
    message("Returning list")
    return(list_out)
  }
  if(requireNamespace("data.table")) {
    out_dt <- data.table::rbindlist(list_out[list_elements_sf])
    return(sf::st_as_sf(out_dt))
  } else {
    do.call(rbind, list_out[list_elements_sf])
  }
}
#' @export
route.Spatial <- function(from = NULL, to = NULL, l = NULL,
                     route_fun = stplanr::route_cyclestreets,
                     n_print = 10, list_output = FALSE, cl = NULL, ...) {

  # error msg in case routing fails
  error_fun <- function(e) {
    warning(paste("Fail for line number", i))
    e
  }
  FUN <- match.fun(route_fun)
  # generate od coordinates
  ldf <- dplyr::as_tibble(od_coords(from, to, l))
  # calculate line data frame
  if(is.null(l)) {
    l <- od2line(ldf)
  }


  # pre-allocate objects
  rc <- as.list(rep(NA, nrow(ldf)))
  rg <- sf::st_sfc(lapply(1:nrow(ldf), function(x) {
    sf::st_linestring(matrix(as.numeric(NA), ncol = 2))
  }))

  rc[[1]] <- FUN(from = c(ldf$fx[1], ldf$fy[1]), to = c(ldf$tx[1], ldf$ty[1]), ...)
  rdf <- dplyr::as_tibble(matrix(ncol = ncol(rc[[1]]@data), nrow = nrow(ldf)))
  names(rdf) <- names(rc[[1]])

  rdf[1, ] <- rc[[1]]@data[1, ]
  rg[1] <- sf::st_as_sfc(rc[[1]])

  if (nrow(ldf) > 1) {
    for (i in 2:nrow(ldf)) {
      rc[[i]] <- tryCatch({
        FUN(from = c(ldf$fx[i], ldf$fy[i]), to = c(ldf$tx[i], ldf$ty[i]), ...)
      }, error = error_fun)
      perc_temp <- i %% round(nrow(ldf) / n_print)
      # print % of distances calculated
      if (!is.na(perc_temp) & perc_temp == 0) {
        message(paste0(round(100 * i / nrow(ldf)), " % out of ", nrow(ldf), " distances calculated"))
      }

      rdf[i, ] <- rc[[i]]@data[1, ]
      rg[i] <- sf::st_as_sf(rc[[i]])$geometry
    }
  }

  r <- sf::st_sf(geometry = rg, rdf)

  if (list_output) {
    r <- rc
  }

  r


}

#' Route on local data using the dodgr package
#'
#' @inheritParams route
#' @param net sf object representing the route network
#' @family routes
#' @export
#' @examples
#' # if (requireNamespace("dodgr")) {
#' #   from <- c(-1.5327, 53.8006) # from <- geo_code("pedallers arms leeds")
#' #   to <- c(-1.5279, 53.8044) # to <- geo_code("gzing")
#' #   # next 4 lines were used to generate `stplanr::osm_net_example`
#' #   # pts <- rbind(from, to)
#' #   # colnames(pts) <- c("X", "Y")
#' #   # net <- dodgr::dodgr_streetnet(pts = pts, expand = 0.1)
#' #   # osm_net_example <- net[c("highway", "name", "lanes", "maxspeed")]
#' #   r <- route_dodgr(from, to, net = osm_net_example)
#' #   plot(osm_net_example$geometry)
#' #   plot(r$geometry, add = TRUE, col = "red", lwd = 5)
#' # }
route_dodgr <- function(from = NULL,
           to = NULL,
           l = NULL,
           net = NULL
           # ,
           # return_net = FALSE
  ) {
  message("remotes::install_github('ropensci/stplanr', ref = 'dodgr') # working version")
    # if (!requireNamespace("dodgr", quietly = TRUE)) {
    #   stop("dodgr must be installed for this function to work.")
    # }
    # od_coordinate_matrix <- od_coords(from, to, l)
    # to_coords <- od_coordinate_matrix[, 3:4, drop = FALSE]
    # fm_coords <- od_coordinate_matrix[, 1:2, drop = FALSE]
    # # Try to get route network if net not provided
    # if (is.null(net)) {
    #   pts <- rbind(fm_coords, to_coords)
    #   net <- dodgr::dodgr_streetnet(pts = pts, expand = 0.2)
    #   message("Network not provided, fetching network using dodgr_streetnet")
    # }
    #
    # ckh <- dodgr::dodgr_cache_off()
    # suppressMessages(
    #   ways_dg <- dodgr::weight_streetnet(net)
    # )
    #
    # verts <- dodgr::dodgr_vertices(ways_dg) # the vertices or points for routing
    # # suppressMessages ({
    # from_id <- unique(verts$id[dodgr::match_pts_to_graph(verts, fm_coords,
    #   connected = TRUE
    # )])
    # to_id <- unique(verts$id[dodgr::match_pts_to_graph(verts, to_coords,
    #   connected = TRUE
    # )])
    # # })
    # dp <- dodgr::dodgr_paths(ways_dg, from = from_id, to = to_id)
    # paths <- lapply(dp, function(i) {
    #   lapply(i, function(j) {
    #     if (is.null(j)) {
    #       return(NULL)
    #     }
    #     res <- verts[match(j, verts$id), c("x", "y")]
    #     sf::st_linestring(as.matrix(res))
    #   })
    # })
    # nms <- as.character(unlist(lapply(paths, function(i) names(i))))
    # from_to <- do.call(rbind, strsplit(nms, "-"))
    # from_xy <- fm_coords[match(from_to[, 1], unique(from_to[, 1])), , drop = FALSE]
    # to_xy <- fm_coords[match(from_to[, 2], unique(from_to[, 2])), , drop = FALSE]
    #
    # # remove any NULL paths:
    # paths <- unlist(paths, recursive = FALSE)
    # index <- which(vapply(paths, is.null, logical(1)))
    # if (any(index)) {
    #   message("unable to trace ", length(index), " path(s)")
    #   message("Failed path index numbers are:")
    #   message(list(as.integer(index)))
    # }
    # index <- which(!seq(paths) %in% index)
    # paths <- sf::st_sfc(paths[index], crs = 4326)
    # sf::st_sf(
    #   from = from_to[index, 1],
    #   from_x = from_xy [index, 1],
    #   from_y = from_xy [index, 2],
    #   to = from_to[index, 2],
    #   to_x = to_xy [index, 1],
    #   to_y = to_xy [index, 2],
    #   geometry = paths
    # )
}

route_i <- function(FUN, ldf, i, l, ...){
  error_fun <- function(e) {
    e
  }
  tryCatch({
    single_route <- FUN(ldf[i, 1:2], ldf[i, 3:4], ...)
    sf::st_sf(cbind(
      sf::st_drop_geometry(l[rep(i, nrow(single_route)), ]),
      route_number = i,
      sf::st_drop_geometry(single_route)
    ),
    geometry = single_route$geometry)
  }, error = error_fun)
}

route_l <- function(FUN, ldf, i, l, ...){
  error_fun <- function(e) {
    e
  }
  tryCatch({
    single_route <- FUN(ldf[i, 1:2], ldf[i, 3:4], ...)
  }, error = error_fun)
}

most_common_class_of_list <- function(l, class_to_find = "sf") {
  class_out <- sapply(l, function(x) class(x)[1])
  most_common_class <- names(sort(table(class_out), decreasing = TRUE)[1])
  message("Most common output is ", most_common_class)
  is_class <- class_out == class_to_find
  is_class
}

