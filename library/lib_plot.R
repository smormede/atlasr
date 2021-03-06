#
#     Plot data viewed from the South Pole
#
# The plot uses ggplot2 rather than base graphics, because it eases
# the projection and mapping of colours.
#
# (c) Copyright 2011 Jean-Olivier Irisson
#     GNU General Public License v3
#
#-----------------------------------------------------------------------------


## Toolbox functions
#-----------------------------------------------------------------------------

polar_proj <- function(projection="stereographic", orientation=c(-90,0,0)) {
  #
  # Easy access to a suitable polar projection
  # NB: view from south pole (-90)
  #
  suppressPackageStartupMessages(require("ggplot2", quietly=TRUE))
  suppressPackageStartupMessages(require("mapproj", quietly=TRUE))
  c <- coord_map(projection=projection, orientation=orientation)
  return(c)
}


scale_brewerc <- function(aesthetic=c("fill", "colour"), type=c("div", "seq"), palette=1, ...) {
  #
  # Continuous colour scales based on ColorBrewer palettes
  # http://colorbrewer2.org/
  # NB: scale_fill/colour_brewer currently work for discrete variables only in ggplot
  #
  # aesthetic   which type of aesthetic to use
  # type        one of seq (sequential) or div (diverging)
  # palette     if a string, will use that named palette.
  #             if a number, will index into the list of palettes of appropriate 'type'
  # ...         passed to scale_fill/colour_gradientn
  #

  suppressPackageStartupMessages(require("RColorBrewer", quietly=TRUE))
  palInfo <- brewer.pal.info
  palInfo <- palInfo[palInfo$category %in% c("div", "seq"),]

  # get palette name
  if (is.numeric(palette)) {
    type <- match.arg(type)
    palette <- row.names(palInfo[palInfo$category == type,])[palette]
  } else {
    palette <- match.arg(palette, row.names(palInfo))
  }

  # compute the colours
  # maxN <- palInfo[palette,"maxcolors"]
  colours <- brewer.pal(n=6, name=palette)
  # Nb: using the maximum range of colors gives palettes that are a little too saturated to be well behaved in a a continuous gradient

  # reverse the colour scale because it matches the direction of the data better
  colours <- rev(colours)

  # call the appropriate function
  aesthetic <- match.arg(aesthetic)
  s <- switch(aesthetic,
          fill = scale_fill_gradientn(..., colours=colours),
          colour = scale_colour_gradientn(..., colours=colours)
  )

  return(s)
}

scale_fill_brewerc <- function(...) { scale_brewerc(..., aesthetic="fill") }
scale_colour_brewerc <- function(...) { scale_brewerc(..., aesthetic="colour") }
scale_color_brewerc <- scale_colour_brewerc


plot.pred <- function(x, ...) {
  #
  # Generic for the plot of predictions from a model
  #
  UseMethod("plot.pred")
}


## Plotting functions
#-----------------------------------------------------------------------------

polar.ggplot <- function(data, mapping=aes(), geom=c("point", "tile"), lat.precision=NULL, lon.precision=NULL, coast=NULL, ...) {
  #
  # data          data frame with columns lat, lon, and variables to plot
  # mapping       a call to `aes()` which maps a variable to a plotting
  #               aesthetic characteristic (fill, colour, size, alpha, etc.)
  # geom          the type of plot ("geometry" in ggplot parlance) to produce
  #               = points (the default) or tiles (possibly better looking, longer)
  # lat.precision
  # lon.precision the precision at which lat and lon are considered
  #               (in degrees). If they are larger than the original
  #               precision, the data is *subsampled* to those locations
  #               i.e. some data is actually dropped. If you want to average or sum
  #               the data per cell, use rasterize() in lib_data.R
  # coast         coastline geom, if none is provided, a basic coastline is drawn
  # ...           passed to the appropriate geom
  #

  suppressPackageStartupMessages(require("plyr", quietly=TRUE))
  suppressPackageStartupMessages(require("ggplot2", quietly=TRUE))
  suppressPackageStartupMessages(require("stringr", quietly=TRUE))

  # Check arguments
  # geoms
  geom <- match.arg(geom)

  # allow lon/lat to be called more liberally
  names(data)[tolower(names(data)) %in% c("latitude","lat")] <- "lat"
  names(data)[tolower(names(data)) %in% c("longitude","lon","long")] <- "lon"
  # check that we have something that looks like lat and lon
  if (! all(c("lat","lon") %in% names(data)) ) {
    stop("Need two columns named lat and lon to be able to plot\nYou have ", paste(names(data), collapse=", "))
  }

  # if new precisions are specified for lat or lon, subsample the data
  if (!is.null(lat.precision)) {
    # compute the vector of latitudes
    lats <- unique(data$lat)
    # regrid latitudes
    lats <- unique(round_any(lats, lat.precision))
    # NB: when the precision in the original data is coarser, nothing changes
    # select points at those latitudes only
    data <- data[data$lat %in% lats,]
  }
  if (!is.null(lon.precision)) {
    lons <- unique(data$lon)
    lons <- unique(round_any(lons, lon.precision))
    data <- data[data$lon %in% lons,]
  }

  # Get and re-cut coastline if none is provided
  if (is.null(coast)) {
    # extract the whole world
    suppressPackageStartupMessages(require("maps", quietly=TRUE))
    coast <- map("world", interior=FALSE, plot=FALSE)
    coast <- data.frame(lon=coast$x, lat=coast$y)
    # restrict the coastline info to what we need given the data
    expand <- 2       # add a little wiggle room
    # compute extent of data
    lats <- range(data$lat) + c(-expand, +expand)
    lons <- range(data$lon) + c(-expand, +expand)
    # re-cut the coastline
    # coast <- coast[coast$lat >= lats[1] & coast$lat <= lats[2] & coast$lon >= lons[1] & coast$lon <= lons[2],]
    coast <- coast[coast$lat <= lats[2] & coast$lon >= lons[1] & coast$lon <= lons[2],]

    # prepare the geom
    coast <- geom_path(data=coast, na.rm=TRUE, colour="grey50")
    # NB: silently remove missing values which are inherent to coastline data
  }


  # Plot
  # prepare plot
  p <- ggplot(data, aes(x=lon, y=lat)) +
        # stereographic projection
        polar_proj()

  # plot points or tiles depending on the geom argument
  if (geom == "point") {
    # add mapping of size to better cover the space (smaller points near the center)
    mapping = c(aes(size=lat), mapping)
    class(mapping) = "uneval"
    # plot
    p <- p + geom_point(mapping=mapping, ...) + scale_size(range=c(0.5, 1.5), guide=FALSE)
  } else if (geom == "tile"){
    p <- p + geom_tile(mapping=mapping, ...)
  }

  # plot the coastline
  p <- p + coast

  # use nice ColorBrewer colours
  if ("fill" %in% names(mapping)) {
    fill.data <- data[,as.character(mapping$fill)]
    if (is.numeric(fill.data)) {
      # if the data is numeric, use a continuous, diverging scale
      p <- p + scale_fill_brewerc(palette="Spectral", guide="colorbar")
    } else if (is.factor(fill.data)) {
      # if the data is discrete, use a ColorBrewer scale only when possible (less than 12 colours)
      if (nlevels(fill.data)<=12) {
        p <- p + scale_fill_brewer(palette="Set3")
      }
      # otherwise just use the default colours of ggplot
    }
  }
  # same for coulour
  if ("colour" %in% names(mapping)) {
    colour.data <- data[,as.character(mapping$colour)]
    if (is.numeric(colour.data)) {
      p <- p + scale_colour_brewerc(palette="Spectral", guide="colorbar")
    } else if (is.factor(colour.data)) {
      if (nlevels(colour.data)<=12) {
        p <- p + scale_colour_brewer(palette="Set3")
      }
    }
  }

  # no background
  p <- p + theme_bw()

  # nicer, simpler scales
  p <- p +
    # scale_x_continuous(name="", breaks=c(0)) +
    # NB: fails due to a bug in ggplot now, instead use
    opts(axis.text.x=theme_blank(), axis.title.x=theme_blank()) +
    scale_y_continuous(name="Latitude")

  return(p)
}


plot.env.data <- function(variables="", path="env_data", ...) {
  #
  # Plot all environmental data to PNG files
  #
  # variables   only output variables matching this (matches all when "")
  # path        path to environmental database
  #
  suppressPackageStartupMessages(require("stringr", quietly=TRUE))
  suppressPackageStartupMessages(require("ggplot2", quietly=TRUE))
  suppressPackageStartupMessages(require("ncdf", quietly=TRUE))
  suppressPackageStartupMessages(require("reshape2", quietly=TRUE))

  # read all data files
  database <- read.env.data(variables=variables, path=path)

  # identify each element by its name and file of origin
  ncVariables <- names(database)
  ncFiles <- list.env.data(variables=variables, path=path, full=T)
  for (i in seq(along=database)) {
    database[[i]]$variable <- ncVariables[i]
    database[[i]]$file <- ncFiles[i]
  }

  message("-> Plot variables")

  # loop on all files
  l_ply(database, function(x) {

    # convert into a data.frame, for ggplot
    d <- melt(x$z)
    names(d) <- c("x", "y", "z")
    d$x <- x$x[d$x]
    d$y <- x$y[d$y]

    # better variable name
    variable <- str_replace_all(x$variable, "_", "\n")

    # png file to plot into
    file <- str_replace(x$file, "\\.nc$", ".png")

    # plot in the png file
    png(file=file, width=1200, height=900, units="px", res=90)

    p <- ggplot(d) +
      # plot points
      geom_point(aes(x=x, y=y, colour=z), size=0.5) +
      # nice colour gradient
      scale_colour_brewer(name=variable, palette="Spectral") +
      # blank theme
      opts(panel.background=theme_blank(),
           panel.grid.major=theme_blank(),
           axis.ticks=theme_blank(),
           axis.title.x=theme_blank(),
           axis.title.y=theme_blank(),
           axis.text.x=theme_blank(),
           axis.text.y=theme_blank(),
           plot.margins=c(0,0,0,0)
      ) +
      # polar view
      polar_proj()
    print(p)

    dev.off()

    # cleanup
    rm(d, p)

    return(NULL)

  }, .progress="text")

  return(invisible(NULL))
}