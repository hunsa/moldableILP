###############################################################################
# SCHEDULING INDEPENDENT MOLDABLE TASKS ON MULTI-CORES WITH GPUS
# Copyright (C) 2015 Sascha Hunold <sascha@hunoldscience.net>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###############################################################################

library(stringr)

basedir <- function(fname){
  argv <- commandArgs(trailingOnly = FALSE)
  base_dir <- dirname(substring(argv[grep("--file=", argv)], 8))
}

suppressWarnings(library('optparse'))

scriptPath <- basedir()

source(file.path(scriptPath, "scheduleR.R"), chdir = TRUE)

my_option_list <- list(
  make_option(c("-c","--csvdir"), action="store", dest="csvdir",
              help="directory with csv files"),
  make_option(c("-i","--indir"), action="store", dest="indir",
              help="directory with problem instances (.in)"),
  make_option(c("-o","--outdir"), action="store", dest="outdir",
              help="directory for output files")
)

uargs <- parse_args(OptionParser(option_list = my_option_list))

uargs

in_files <- list.files(uargs$indir, pattern = ".*\\.in$", full.names = TRUE)
#in_files

csv_files <- list.files(uargs$csvdir, pattern = ".*\\.csv", full.names = TRUE)
#csv_files


outfile <- file.path(uargs$outdir, "test.pdf")

pdf(outfile, width = 20, height = 30)

total_instances <- length(in_files)
instances_done <- 0

for(infile in in_files) {
  bn <- basename(infile)
  listplots <- list()
  prob <- str_split(bn, "\\.")[[1]][1]
  print(infile)

  # find largest makespan
  ylim <- 0
  for(csvf in csv_files) {
    bn2 <- basename(csvf)
    if( grepl(paste0("^", prob), bn2) ) {
      df <- read.csv2(csvf, header = TRUE, dec = ".")
      ylim <- max(ylim, df$etime)
    }
  }

  # plot schedules and set common bound "ylim"
  for(csvf in csv_files) {
    bn2 <- basename(csvf)
    if( grepl(paste0("^", prob), bn2) ) {
      print(csvf)
      p <- make_plot(csvf, infile, ylim)
      listplots[[length(listplots)+1]] <- p
    }
  }
  #pfinal <- arrangeGrob(grobs=listplots, ncol = 2)
  #plot(pfinal)
  grid.arrange(grobs=listplots, ncol = 2)

  instances_done <- instances_done + 1
  perc <- instances_done/total_instances * 100
  print(paste0("instances done: ", instances_done, " percent: ", perc, "%"))

}

dev.off()
