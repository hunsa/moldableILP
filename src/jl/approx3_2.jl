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

using PyCall
using Logging

include("approx_common.jl")

unshift!(PyVector(pyimport("sys")["path"]), MyPythonPath)
@pyimport build_approx_schedule

include("solve_mip.jl")

stats = Dict()

function find_lambda_by_bisect_search(params::Dict, input::SchedulerInput, lower::Float64, upper::Float64)
    r_lambda = -1

    stats["nb_of_iterations"] = 0
    stats["mean_solve_time"]  = 0.0
    stats["total_solve_time"] = 0.0
    stats["nb_free_var"] = Array{Int64}[]
    stats["avg_nb_var"]  = Float64[]

    while upper/lower > getCutoffRatio()

        bisect = lower + (upper-lower)/2.0

        debug("bisect=", bisect)

        t1 = time_ns()
        sol_hash = has_solution_for_lambda(input, bisect)
        t2 = time_ns()

        sol_stats = sol_hash["stats"]
        if get(sol_stats, "nb_free_var", -1) != -1
          push!(stats["nb_free_var"], sol_stats["nb_free_var"])
          avg_nb_var = sum(sol_stats["nb_free_var"]) / float(input["meta"]["n"])
          push!(stats["avg_nb_var"], avg_nb_var)
        end

        stats["nb_of_iterations"] += 1
        stats["total_solve_time"] += (t2-t1)/1e9

        sol_found = sol_hash["has_solution"]
        if sol_found
            upper = bisect
            r_lambda = bisect
        else
            lower = bisect
        end
    end

    stats["mean_solve_time"] = stats["total_solve_time"] / float(stats["nb_of_iterations"])

    return r_lambda
end

function solve_problem(instance::SchedulerInput,
                       inst_params::ScheduleInstanceParams)

    lb = compute_lowerbound(instance)
    ub = compute_upperbound(instance)

    debug("lb:", lb)
    debug("ub:", ub)

    params = Dict()
    empty!(stats)

    lambda = find_lambda_by_bisect_search(params, instance, lb, ub)

    if lambda == -1
        @printf("could not find solution\n")
    else
        @printf "best lambda: %f\n" lambda

        for key in keys(stats)
            @printf("%s: %s\n", key, stats[key])
        end

        solution = solve_problem_instance(instance, lambda)
        sol_hash = create_instance_solution(instance, solution)
        sol_hash["lambda"] = lambda
        build_approx_schedule.build_schedule(instance, sol_hash, lambda, inst_params.jedfile, inst_params.csvfile)

#        println( length(keys(sol_hash["task_hash"])) )
    end

end


#Logging.configure(level=DEBUG)
#Logging.configure(level=INFO)

function test_approx_solver()

#   if length(ARGS) < 2
#       println("julia find_approx_solution.jl <instance_fname> <solution_fname> <jedule_fname>")
#   else
#       instance = SchedulerInput(JSON.parsefile(ARGS[1]))
#       solve_problem(instance, ARGS[2], ARGS[3])
#   end

#    infile = "/Users/sascha/work/progs/perfpack/task_sched/2015-01-imts/000-test_small_instances_opt-2015-01-12-1710/02-exp/input/instances/problem_n10_m8_k2_i0.in"
#    infile = "/Users/sascha/work/progs/perfpack/task_sched/2015/002-sched_julia-2015-09-03-2153/02-exp/input/instances/problem_n1000_m256_k16_i4.in.bz2"
#    infile = "/Users/sascha/work/progs/perfpack/task_sched/2015/002-sched_julia-2015-09-03-2153/02-exp/input/instances/problem_n1000_m384_k32_i0.in.bz2"
    infile = "/Users/sascha/work/progs/perfpack/task_sched/2016/000-sched_julia_lpt_changed-2016-03-09-1307/02-exp/input/instances/problem_n10_m4_k2_i9.in.bz2"
    instance = load_scheduling_instance(infile)

    solve_problem(instance,
      "/Users/sascha/tmp/approxsched/julia.out",
      "/Users/sascha/tmp/approxsched/julia.jed",
      "/Users/sascha/tmp/approxsched/julia.csv")

end
