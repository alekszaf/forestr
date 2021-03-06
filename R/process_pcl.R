#' Process single PCL transects.
#'
#' \code{process_pcl} imports and processes a single PCL transect.
#'
#' This function imports raw pcl data or existing data frames of pcl data and writes
#' all data and analysis to a series of .csv files in an output directory (output)
#' keeping nothing in the workspace.
#'
#' \code{process_pcl} uses a workflow that cuts the data into 1 meter segments with
#' z and x positions in coordinate space where x referes to distance along the ground
#' and z refers to distance above the ground. Data are normalized based on
#' light extinction assumptions from the Beer-Lambert Law to account for light saturation.
#' Data are then summarized and metrics of canopy structure complexity are calculated.
#'
#' \code{process_pcl} will write multiple output files to disk in an output directory that
#'  \code{process_pcl} creates within the work directing. These files include:
#'
#' 1. an output variables file that contains a list of CSC variables and is
#' written by the subfunction \code{write_pcl_to_csv}
#' 2. a summary matrix, that includes detailed information on each vertical column
#' of LiDAR data written by the subfunction \code{write_summary_matrix_to_csv}
#' 3. a hit matrix, which is a matrix of VAI at each x and z position, written by the
#' subfunction \code{write_hit_matrix_to_pcl}
#' 4. a hit grid, which is a graphical representation of VAI along the x and z coordinate space.
#' 5. optionally, plant area/volume density profiles can be created by including
#' \code{pavd = TRUE} that include an additional histogram with the optional
#' \code{hist = TRUE} in the \code{process_pcl} call.
#'
#'
#' @param f  the name of the filename to input <character> or a data frame <data frame>.
#' @param user_height the height of the laser off the ground as mounted on the user
#' in meters. default is 1 m
#' @param marker.spacing distance between markers, defaults is 10 m
#' @param max.vai the maximum value of column VAI. The default is 8. Should be
#' a max value, not a mean.
#' @param pavd logical input to include Plant Area Volume Density Plot from {plot_pavd},
#' if TRUE it is included, if FALSE, it is not.
#' @param hist logical input to include histogram of VAI with PAVD plot, if
#' TRUE it is included, if FALSE, it is not.
#' @return writes the hit matrix, summary matrix, and output variables to csv
#' in an output folder, along with hit grid plot
#'
#' @keywords pcl processing
#' @export
#'
#' @seealso
#' \code{\link{process_multi_pcl}}
#'
#'
#' @examples
#' # Link to stored, raw PCL data in .csv form
#' uva.pcl <- system.file("extdata", "UVAX_A4_01W.csv", package = "forestr")
#'
#' # Run process complete PCL transect, store output to disk
#' process_pcl(uva.pcl, marker.spacing = 10, user_height = 1.05,
#' max.vai = 8, pavd = FALSE, hist = FALSE)
#'
#'
#' # with data frame
#' process_pcl(osbs, marker.spacing = 10, user_height = 1.05,
#' max.vai = 8, pavd = FALSE, hist = FALSE)
#'
#'

process_pcl<- function(f, user_height, marker.spacing, max.vai, pavd = FALSE, hist = FALSE){
  xbin <- NULL
  zbin <- NULL
  vai <- NULL

  # If missing user height default is 1 m.
  if(missing(user_height)){
    user_height = 1
  }

  # If missing marker.spacing, default is 10 m.
  if(missing(marker.spacing)){
    marker.spacing = 10
  }

  # If missing max.vai default is 8
  if(missing(max.vai)){
    max.vai = 8
  }
#
  if(is.character(f) == TRUE) {

  # Read in PCL transect.
  df<- read_pcl(f)

    # Cuts off the directory info to give just the filename.
  filename <- sub(".*/", "", f)

  } else if(is.data.frame(f) == TRUE){
    df <- f
    filename <- deparse(substitute(f))
  } else {
    warning('This is not the data you are looking for')
  }

  # cuts out erroneous high values
  #df <- df[!(df$return_distance >= 50), ]

  # Calculate transect length.
  transect.length <- get_transect_length(df, marker.spacing)

  #error checking transect length
  message("Transect Length")
  print(transect.length)

  # Desginates a LiDAR pulse as either a sky hit or a canopy hit
  df2 <- code_hits(df)

  message("Table of sky hits")
  print(table(df2$sky_hit))

  # Adjusts by the height of the  user to account for difference in laser height to
  # ground in   meters==default is 1 m.
  df3 <- adjust_by_user(df2, user_height)

  # First-order metrics of sky and cover fraction.
  csc.metrics <- csc_metrics(df3, filename, transect.length)

  # Splits transects from code into segments (distances between markers as designated by        marker.spacing
  # and chunks (1 m chunks in each marker).
  test.data.binned <- split_transects_from_pcl(df3, transect.length, marker.spacing)

  # Makes matrix of z and x coordinated pcl data.
  m1 <- make_matrix(test.data.binned)

  # Normalizes date by column based on assumptions of Beer-Lambert Law of light extinction vertically
  # through the canopy.
  m2 <- normalize_pcl(m1)

  # Calculates VAI (vegetation area index m^ 2 m^ -2).
  m5 <- calc_vai(m2, max.vai)
  # Summary matrix.
  summary.matrix <- make_summary_matrix(test.data.binned, m5)
  rumple <- calc_rumple(summary.matrix)
  clumping.index <- calc_gap_fraction(m5)

  variable.list <- calc_rugosity(summary.matrix, m5, filename)

  # effective number of layers
  enl <- calc_enl(m5)

  output.variables <- combine_variables(variable.list, csc.metrics, rumple, clumping.index, enl)

  #output procedure for variables
  outputname = substr(filename,1,nchar(filename)-4)
  outputname <- paste(outputname, "output", sep = "_")
  dir.create("output", showWarnings = FALSE)
  output_directory <- "./output/"
  print(outputname)
  print(output_directory)

  write_pcl_to_csv(output.variables, outputname, output_directory)
  write_summary_matrix_to_csv(summary.matrix, outputname, output_directory)
  write_hit_matrix_to_csv(m5, outputname, output_directory)




  #get filename first
  plot.filename <- tools::file_path_sans_ext(filename)
  plot.filename.full <- paste(plot.filename, "hit_grid", sep = "_")
  plot.filename.pavd <- paste(plot.filename, "pavd", sep = "_")

  plot.file.path.hg <- file.path(paste(output_directory, plot.filename.full, ".png", sep = ""))
  plot.file.path.pavd <- file.path(paste(output_directory, plot.filename.pavd, ".png", sep = ""))

  vai.label =  expression(paste(VAI~(m^2 ~m^-2)))

  #setting up VAI hit grid
  m6 <- m5
  m6$vai[m6$vai == 0] <- NA
  message("No. of NA values in hit matrix")
  print(sum(is.na(m6$vai)))
  #x11(width = 8, height = 6)
  hit.grid <- ggplot2::ggplot(m6, ggplot2::aes(x = xbin, y = zbin))+
    ggplot2::geom_tile(ggplot2::aes(fill = vai))+
    ggplot2::scale_fill_gradient(low="gray88", high="dark green",
                                 na.value = "white",
                                 limits=c(0, 8),
                                 name=vai.label)+
    #scale_y_continuous(breaks = seq(0, 20, 5))+
    # scale_x_continuous(minor_breaks = seq(0, 40, 1))+
    ggplot2::theme(axis.line = ggplot2::element_line(colour = "black"),
          panel.grid.major = ggplot2::element_blank(),
          panel.grid.minor = ggplot2::element_blank(),
          panel.background = ggplot2::element_blank(),
          axis.text.x = ggplot2::element_text(size = 14),
          axis.text.y = ggplot2::element_text(size = 14),
          axis.title.x = ggplot2::element_text(size = 20),
          axis.title.y = ggplot2::element_text(size = 20))+
    ggplot2::xlim(0,transect.length)+
    ggplot2::ylim(0,41)+
    ggplot2::xlab("Distance along transect (m)")+
    ggplot2::ylab("Height above ground (m)")+
    ggplot2::ggtitle(filename)+
    ggplot2::theme(plot.title = ggplot2::element_text(lineheight=.8, face="bold"))

  ggplot2::ggsave(plot.file.path.hg, hit.grid, width = 8, height = 6, units = c("in"))

  # PAVD
  if(pavd == TRUE && hist == FALSE){

    plot_pavd(m5, filename, plot.file.path.pavd, output.file = TRUE)

  }
  if(pavd == TRUE && hist == TRUE){

    plot_pavd(m5, filename, plot.file.path.pavd, hist = TRUE, output.file = TRUE)
  }

}
