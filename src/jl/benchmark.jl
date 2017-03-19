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

import JSON

using Logging
using PyCall
using ArgParse

include("approx_common.jl")
include("benchmark_common.jl")

unshift!(PyVector(pyimport("sys")["path"]), MyPythonPath)

include("approx2.jl")
include("approx3_2.jl")

#unshift!(PyVector(pyimport("sys")["path"]), "./src/python/")
@pyimport apply_heft
#@pyimport bz2

function run_benchmark(params::SchedulerParams)

  fnames = readdir(params.inputdir)

  filter!(x -> !isfile(x),fnames)
  filter!(x -> endswith(x, ".in") || endswith(x, ".in.bz2"), fnames)
  debug(fnames)

  if !isdir(params.outdir)
    error(params.outdir, " invalid")
  end

  # do the epxeriments with the first file / instance twice
  # the first instance should be significantly slower than the others
  for fname in unshift!(fnames, fnames[1])
    debug(fname)

    instance_fname = joinpath(params.inputdir, fname)
    instance = load_scheduling_instance(instance_fname)

    alg = "approx2"
    paths = get_output_file_names(fname, params.outdir, alg)
#    println(paths)
    println("alg: " * alg)
    @printf "instance: %s\n" fname
    inst_params = ScheduleInstanceParams(instance_fname, "", "")
    if params.create_jedule == true
      inst_params.jedfile = paths["jed_fname"]
    end
    if params.create_csv == true
      inst_params.csvfile = paths["csv_fname"]
    end
    solve_problem_2approx(instance, inst_params)

    alg = "approx32"
    paths = get_output_file_names(fname, params.outdir, alg)
    println("alg: " * alg)
    @printf "instance: %s\n" fname
    inst_params = ScheduleInstanceParams(instance_fname, "", "")
    if params.create_jedule == true
      inst_params.jedfile = paths["jed_fname"]
    end
    if params.create_csv == true
      inst_params.csvfile = paths["csv_fname"]
    end
    solve_problem(instance, inst_params)

    for prio in ["lpt", "spt", "ratio"]
      for seq_only in [0, 1]
        println("alg: heft")
        @printf "instance: %s\n" fname
        alg = "heft" * "_" * prio * "_" * string(seq_only)
        paths = get_output_file_names(fname, params.outdir, alg)
        inst_params = ScheduleInstanceParams(instance_fname, "", "")
        jed_fname = ""
        if params.create_jedule == true
          jed_fname = paths["jed_fname"]
        end
        csv_fname = ""
        if params.create_csv == true
          csv_fname = paths["csv_fname"]
        end
        apply_heft.build_heft_schedule(instance, seq_only, prio, jed_fname, csv_fname)
      end
    end

  end

end

#Logging.configure(level=DEBUG)
#Logging.configure(level=INFO)
Logging.configure(level=WARNING)


s = ArgParseSettings()
@add_arg_table s begin
    "--in", "-i"
      help = "directory with instances"
      arg_type = AbstractString
      required = true
    "--out", "-o"
      help = "directory for output files"
      arg_type = AbstractString
      required = true
    "--jedule", "-j"
      help = "create jedule output"
      action = :store_true
    "--csv", "-c"
      help = "create csv output"
      action = :store_true
end

parsed_args = parse_args(ARGS, s)

#print(parsed_args)

scheduler_params = SchedulerParams(parsed_args["in"], parsed_args["out"], parsed_args["jedule"], parsed_args["csv"])
run_benchmark(scheduler_params)

# if length(ARGS) < 2
#     println("julia benchmark.jl <instance_dirname> <output_dirname>")
# else
#     run_benchmark(ARGS[1], ARGS[2])
# end
