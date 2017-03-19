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


suppressWarnings(library('optparse'))
suppressWarnings(library('rjson'))

# we keep this beta distribution and scale it between 0.1 and 1.5
gpuspeedup <- function(min, max, mean, var) {
  shape1 <- 3
  shape2 <- 5
  val <- rbeta(1, shape1, shape2)
  val <- min + val * (max-min)
  val
}

gpuspeedup_old <- function(min, max, mean, var) {
  done <- FALSE
  while( done == FALSE ) {
    val <- rnorm(1, mean = mean, sd = var)
    if( val >= min && val <= max ) {
      done = TRUE
    }
  }
  val
}

# set.seed(1)
#
# min <- 0.1
# max <- 1.5
# mean <- 0.2
# sd   <- 0.5

# n_tasks <- 1000
# speedups <- 1:1000

# vals <- sapply(speedups, function(x)  pmyspeedup2(min, max, mean, sd))
# min(vals)
# max(vals)
# hist(vals, breaks=30)

# while(1) {
#   vals <- sapply(speedups, function(x)  pmyspeedup2(min, max, mean, sd))
#   print(max(vals))
#   if( max(vals) > 1.5 ) {
#     break
#   }
# }

partime <- function(nb_procs, seq_time, seqfrac=0) {
  ptime <- seq_time * seqfrac +  (1 - seqfrac)*seq_time / nb_procs
  ptime
}

# max_factor: how much faster it is than sequentially
# e.g., 0.1 means 10 times faster on GPU
gputime1 <- function(seq_time, min_factor=0.1, max_factor=1.5, gpu_time_mean=0.5, gpu_time_sd=0.5) {
  # gpu_time_sd is ignored right now
  val <- gpuspeedup_old(min_factor, max_factor, gpu_time_mean, gpu_time_sd)

  #val <- rnorm(1, mean = gpu_time_mean, sd = gpu_time_sd)
  #val <- max(min_factor, val)
  #val <- min(max_factor, val)
  val * seq_time
}

get_seq_time <- function(taskid, min_time, max_time) {
  #  val <- runif(1, min = min_time, max = max_time)
  shape1 <- 3
  shape2 <- 5
  val <- rbeta(1, shape1, shape2)
  val <- min_time + val * (max_time-min_time)
  val
}

my_option_list <- list(
  make_option(c("-s","--seed"), action="store", dest="myseed",
              help="use random seed", default=-1),
  make_option(c("-n","--ntasks"), action="store", dest="ntasks",
              help="number of tasks", default=10),
  make_option(c("-m","--mcores"), action="store", dest="mcores",
              help="number of cores", default=8),
  make_option(c("-k","--kgpus"), action="store", dest="kgpus",
              help="number of GPUs", default=1),
  make_option(c("-o","--outpath"), action="store", dest="outpath",
              help="filename for output"),
  make_option("--sfrac_min", action="store", dest="sfrac_min",
              help="minimum sequential fraction", default=0),
  make_option("--sfrac_max", action="store", dest="sfrac_max",
              help="maximum sequential fraction", default=0.5),
  make_option("--gpu_min_factor", action="store", dest="gpu_fac_min",
              help="minimum gpu factor (multiplied by time on m cores)", default=0.1),
  make_option("--gpu_max_factor", action="store", dest="gpu_fac_ax",
              help="minimum gpu factor (multiplied by time on m cores)", default=1.5),
  make_option("--gpu_mean_factor", action="store", dest="gpu_fac_mean",
              help="minimum gpu factor mean", default=0.2),
  make_option("--gpu_sd_factor", action="store", dest="gpu_fac_sd",
              help="minimum gpu factor standard deviation", default=10),
  make_option("--min_seq_time", action="store", dest="min_seq_time_cpu",
              help="minimum sequential CPU time", default=10),
  make_option("--max_seq_time", action="store", dest="max_seq_time_cpu",
              help="maximum sequential CPU time", default=100)
)

uargs <- parse_args(OptionParser(option_list = my_option_list))

#print(uargs)

if(uargs$myseed != -1) {
  set.seed(uargs$myseed)
}

partime_func <- partime
gpu_time_func <- gputime1

seq_times <- sapply(1:uargs$ntasks, get_seq_time, min=uargs$min_seq_time_cpu, max=uargs$max_seq_time_cpu)

df <- data.frame(nb_p = c(1:uargs$mcores))

gpu_times <- list()

for(i in 1:uargs$ntasks) {

  sfrac <- runif(1, min = uargs$sfrac_min, max = uargs$sfrac_max)
#  print(paste("sfrac:", sfrac))

  par_times <- sapply(1:uargs$mcores, partime_func, seq_time = seq_times[i],
                      seqfrac=sfrac)
#  print(par_times)

  task_str <- paste("t", i, sep="")

  df[task_str] <- par_times

  gpu_time <- sapply(tail(par_times,1), gpu_time_func)
  gpu_times[task_str] <- gpu_time
}

#print(gpu_times)

tasklabels <- sapply(1:uargs$ntasks, function(x) paste("t",x,sep=""))

meta_data <- list(
  "n" = uargs$ntasks,
  "m" = uargs$mcores,
  "k" = uargs$kgpus
)

output_list <- list(meta=meta_data, cpudata=df, gpudata=gpu_times)


if( is.null(uargs$outpath) ) {
  print(rjson::toJSON(output_list))
} else {
  fileConn <- file(uargs$outpath)
  writeLines(rjson::toJSON(output_list), fileConn)
  close(fileConn)
}
