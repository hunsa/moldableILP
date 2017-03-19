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

const SchedulerInput = Dict{Any,Any}

MyPythonPath = realpath(joinpath(dirname(@__FILE__),"..","python"))
#MyPythonPath = "/Users/sascha/programming/university/moldableLP_src/src/python/"
#print(MyPythonPath)

type SchedulerParams
  inputdir::AbstractString
  outdir::AbstractString
  create_jedule::Bool
  create_csv::Bool
end

type ScheduleInstanceParams
  infile::AbstractString
  jedfile::AbstractString
  csvfile::AbstractString
end

function compute_lowerbound(data::SchedulerInput)
    lb = 0.0

    for i=1:data["meta"]["n"]
        task_str = get_task_str(i)
        min_cpu_time = minimum( data["cpudata"][task_str] )
        gpu_time = float( data["gpudata"][task_str] )
        min_task_time = min( min_cpu_time, gpu_time )
        lb += min_task_time
    end

    # now we perfectly load balance across all devices
    # even though impossible
    # not very tight lower bound -> could be improved
    lb /= ( data["meta"]["m"] + data["meta"]["k"] )

#    return lb

    # subtlety: to allow convergence of lambda to its smaller value
    # the lower bound should be at the inverse ratio of the scheduling
    # algorithm

    return 2 * lb / 3.0
end

function compute_upperbound(data::SchedulerInput)
    ub = 0.0

    for i=1:data["meta"]["n"]
        task_str = get_task_str(i)
        max_cpu_time = maximum( data["cpudata"][task_str] )
        max_gpu_time = float( data["gpudata"][task_str] )
        max_task_time = max( max_cpu_time, max_gpu_time )
        ub += max_task_time
    end

    return ub
end

function getCutoffRatio()
    return 1.01
end


function get_task_str(task_id)
    string("t", task_id)
end

function get_task_id(task_str::AbstractString)
    return parse(Int,replace(task_str, "t", ""))
end

function get_procs_by_lambda( instance, task_str, lambda_val )
    ret_nb_procs = 100000

    time_arr = instance["cpudata"][task_str]

    for i = 1:instance["meta"]["m"]
        if float(time_arr[i]) <= lambda_val
            ret_nb_procs = i
            break
        end
    end

    return ret_nb_procs
end

function get_time_by_procs( instance, task_str, procs)
    return float(instance["cpudata"][task_str][procs])
end

function load_scheduling_instance(instance_fname::AbstractString)
  if endswith(instance_fname, ".in.bz2")
    zipfile, p = open(`bzcat $(instance_fname)`)
    instance = SchedulerInput(JSON.parse(zipfile))
  else
    instance = SchedulerInput(JSON.parsefile(instance_fname))
  end
  instance
end
