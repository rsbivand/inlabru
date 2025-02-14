% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ggplot.R
\name{gg.SpatialLines}
\alias{gg.SpatialLines}
\title{Geom for SpatialLines objects}
\usage{
\method{gg}{SpatialLines}(data, mapping = NULL, crs = NULL, ...)
}
\arguments{
\item{data}{A \code{SpatialLines} or \code{SpatialLinesDataFrame} object.}

\item{mapping}{Aesthetic mappings created by \code{ggplot2::aes} or \code{ggplot2::aes_}
used to update the default
mapping. The default mapping is
\code{ggplot2::aes(x = .data[[coordnames(data)[1]]], y = .data[[coordnames(data)[2]]], xend = .data[[paste0("end.", coordnames(data)[1])]], yend = .data[[paste0("end.", coordnames(data)[2])]])}.}

\item{crs}{A \code{CRS} object defining the coordinate system to project the data
to before plotting.}

\item{...}{Arguments passed on to \code{ggplot2::geom_segment}.}
}
\value{
A `geom_segment`` return value.
}
\description{
Extracts start and end points of the lines and calls \code{geom_segment} to plot
lines between them. Requires the \code{ggplot2} package.
}
\examples{
\donttest{
  if (require(ggplot2, quietly = TRUE) &&
      require(ggpolypath, quietly = TRUE)) {
    # Load Gorilla data

    data("gorillas", package = "inlabru")

    # Plot Gorilla elevation covariate provided as SpatialPixelsDataFrame.
    # The same syntax applies to SpatialGridDataFrame objects.

    ggplot() +
      gg(gorillas$gcov$elevation)

    # Add Gorilla survey boundary and nest sightings

    ggplot() +
      gg(gorillas$gcov$elevation) +
      gg(gorillas$boundary) +
      gg(gorillas$nests)

    # Load pantropical dolphin data

    data("mexdolphin", package = "inlabru")

    # Plot the pantropiical survey boundary, ship transects and dolphin sightings

    ggplot() +
      gg(mexdolphin$ppoly) + # survey boundary as SpatialPolygon
      gg(mexdolphin$samplers) + # ship transects as SpatialLines
      gg(mexdolphin$points) # dolphin sightings as SpatialPoints

    # Change color

    ggplot() +
      gg(mexdolphin$ppoly, color = "green") + # survey boundary as SpatialPolygon
      gg(mexdolphin$samplers, color = "red") + # ship transects as SpatialLines
      gg(mexdolphin$points, color = "blue") # dolphin sightings as SpatialPoints


    # Visualize data annotations: line width by segment number

    names(mexdolphin$samplers) # 'seg' holds the segment number
    ggplot() +
      gg(mexdolphin$samplers, aes(color = seg))

    # Visualize data annotations: point size by dolphin group size

    names(mexdolphin$points) # 'size' holds the group size
    ggplot() +
      gg(mexdolphin$points, aes(size = size))
  }
}
}
\seealso{
Other geomes for spatial data: 
\code{\link{gg.SpatRaster}()},
\code{\link{gg.SpatialGridDataFrame}()},
\code{\link{gg.SpatialPixelsDataFrame}()},
\code{\link{gg.SpatialPixels}()},
\code{\link{gg.SpatialPoints}()},
\code{\link{gg.SpatialPolygons}()},
\code{\link{gg}()},
\code{\link{gm}()}
}
\concept{geomes for spatial data}
