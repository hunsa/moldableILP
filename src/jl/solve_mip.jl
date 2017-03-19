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
using JuMP
using MathProgBase
#using GLPKMathProgInterface
#using CPLEX
using Gurobi
using Logging

include("approx_common.jl")

function solve_problem_instance(in_stance::Dict, lambda::Float64)
    #m = Model()
    #m = Model(solver=CplexSolver(CPX_PARAM_MIPDISPLAY=1, CPX_PARAM_MIPINTERVAL=1))
    #m = Model(solver=CPLEX.CplexSolver(CPX_PARAM_SCRIND=0))
    m = Model(solver=Gurobi.GurobiSolver(ConcurrentMIP=8,LogToConsole=0))

    #println( in_stance["meta"]["m"] )
    #println( in_stance["meta"]["n"] )

    N = in_stance["meta"]["n"]
    M = in_stance["meta"]["m"]
    K = in_stance["meta"]["k"]
    Q = 7

    gamma_lamb   = ones(Int64,N)
    gamma_12lamb = ones(Int64,N)
    gamma_32lamb = ones(Int64,N)

    work = zeros(N,M)
    pgpu = zeros(N)

    for i=1:N
        task_str = get_task_str(i)
        task_times = in_stance["cpudata"][task_str]
        for j=1:M
            work[i,j] = j * float(task_times[j])
        end
        pgpu[i] = float(in_stance["gpudata"][task_str])
    end

#    println("work")
#    println(work)

#    println("pgpu")
#    println(pgpu)

#    gamma_hash = Dict()

    # first check if all CPU tasks <= lambda or GPU tasks <= lambda
    # if not -> infeasible
    for i = 1:N
        task_str = get_task_str(i)
        if( get_time_by_procs(in_stance, task_str, M) > lambda && pgpu[i] > lambda )
          return Dict("status" => false)
        end
    end

    for i = 1:N
        task_str = get_task_str(i)
        #println(get_task_str(i))
        #println(get_procs_by_lambda(in_stance, get_task_str(i), lambda))

        gamma_val    = get_procs_by_lambda(in_stance, task_str, lambda)
        gamma12_val  = get_procs_by_lambda(in_stance, task_str, lambda / 2)
        gamma32_val  = get_procs_by_lambda(in_stance, task_str, 3 * lambda / 2)

        gamma_lamb[i]   = gamma_val
        gamma_12lamb[i] = gamma12_val
        gamma_32lamb[i] = gamma32_val
    end

#    println("gamma_lamb")
#    println(gamma_lamb)
#    println("gamma_12lamb")
#    println(gamma_12lamb)
#    println("gamma_32lamb")
#    println(gamma_32lamb)


    @variable(m, x[1:N,1:Q], Bin )
    @variable(m, wc >= 0 )
    @variable(m, low1 >= 0, Int )
    @variable(m, up1 >= 0, Int )

    total_nb_var = [ N for i in 1:Q ]

    @objective(m, :Min, wc)

    @expression(m, exp1, sum{
    work[i,1] * ( x[i,1] + x[i,2] ) +
    ( ( gamma_32lamb[i] <= M ) ? work[i, gamma_32lamb[i]] * x[i,3] : gamma_32lamb[i] * x[i,3] ) +
    ( ( gamma_lamb[i] <= M ) ? work[i, gamma_lamb[i]] * x[i,4] : gamma_lamb[i] * x[i,4] ) +
    ( ( gamma_12lamb[i] <= M ) ? work[i, gamma_12lamb[i]] * x[i,5] : gamma_12lamb[i] * x[i,5] )
    ,
    i=1:N
    })

    @constraint(m, exp1 <= wc)

    for j = 1:N
      @constraint(m, sum{ x[j,l], l=1:Q } == 1)
    end


    @expression(m, exp2, sum{ (   gamma_lamb[i] * x[i,4] + gamma_32lamb[i] * x[i,3] ) , i=1:N } )
    @expression(m, exp3, sum{ ( gamma_12lamb[i] * x[i,5] + gamma_32lamb[i] * x[i,3] ) , i=1:N } )

    @constraint(m, exp2 + low1 <= M)
    @constraint(m, exp3 + up1 <= M)

    @constraint(m, sum{ ( pgpu[i] * ( x[i,6] + x[i,7] ) ), i=1:N } <= K * lambda )
    @constraint(m, sum{ x[i,6], i=1:N } <= K )
    @constraint(m, sum{ x[i,2], i=1:N } == low1 + up1 )

    @constraint(m, 0 <= low1 - up1 )
    @constraint(m, low1 - up1 <= 1 )

    for i = 1:N
        task_str = get_task_str(i)

        # set (0) (in paper)
        # check whether task is > lambda / 2 on CORE
        # if so, set x[j,1] = 0
        time_seq = float( in_stance["cpudata"][task_str][1] )
        if time_seq > lambda / 2.0
            @constraint(m, x[i,1] == 0)
            total_nb_var[1] -= 1
        end

        # set (1) (in paper)
        # check whether task time is (<= lambda /2) or (> 3/4 * lambda) on CORE
        # if so, set x[j,2] = 0
        time_seq = float( in_stance["cpudata"][task_str][1] )
        if (time_seq <= lambda / 2.0) || (time_seq > 3.0/4.0 * lambda)
            @constraint(m, x[i,2] == 0)
            total_nb_var[2] -= 1
        end

        # set (2) (in paper)
        # if gamma(j, 3/2 lambda) <= lambda -> task does not belong to set (2) (in paper)
        nbp_lamb32 = gamma_32lamb[i]
        if nbp_lamb32 <= M
            time_lamb32 = get_time_by_procs(in_stance, task_str, nbp_lamb32)
            if time_lamb32 <= lambda
                @constraint(m, x[i,3] == 0)
                total_nb_var[3] -= 1
            end
        end

        # if gamma(j, 3/2 lambda) > m -> it cannot go to set 3 (2 in paper)
        if gamma_32lamb[i] > M
            @constraint(m, x[i,3] == 0)
            total_nb_var[3] -= 1
        end

        # set (3) (in paper)
        # time for gamma(j, lambda) should be > 3/4 lambda
        nbp_lamb = gamma_lamb[i]
        if nbp_lamb <= M
            time_lamb = get_time_by_procs(in_stance, task_str, nbp_lamb)
            if( (time_lamb <= lambda/2.0) || (nbp_lamb==1 && time_lamb <= 3.0/4.0 * lambda && time_lamb >= lambda/2.0) )
               @constraint(m, x[i,4] == 0)
               total_nb_var[4] -= 1
            end
        end

        # if gamma(j, lambda) > m -> it cannot go to set 4 (3 in paper)
        if gamma_lamb[i] > M
            @constraint(m, x[i,4] == 0)
            total_nb_var[4] -= 1
        end

        # set (4) (in paper)
        # if gamma(j,lambda/2) is 1 -> it cannot go to set 5 (4 in the paper)
        if gamma_12lamb[i] == 1
            @constraint(m, x[i,5] == 0)
            total_nb_var[5] -= 1
        end

        # if gamma(j,lambda/2) > m -> it cannot go to set 5 (4 in paper)
        if gamma_12lamb[i] > M
            @constraint(m, x[i,5] == 0)
            total_nb_var[5] -= 1
        end

        time_gpu = float( in_stance["gpudata"][task_str] )

        # set (5) (in paper)
        # task should be greater than lambda /2, if not it cannot go to set (5) (in paper)
        if( (time_gpu <= lambda / 2.0) || (time_gpu > lambda) )
            @constraint(m, x[i,6] == 0)
            total_nb_var[6] -= 1
        end

        # set (6) (in paper)
        # check whether task is <= lambda / 2 on GPU, if not it cannot got to set (6) (in paper)
        # if so, set x[j,7] = 0
        if time_gpu > lambda / 2.0
            @constraint(m, x[i,7] == 0)
            total_nb_var[7] -= 1
        end

    end

#    println("total var:", N*Q)
#    println("real  var:", total_nb_var)

    status = solve(m)

    #writeLP(m, "/Users/sascha/programming/university/gpgpu_dualapprox/examples//scratch/test.lp")
    #writeMPS(m, "/Users/sascha/programming/university/gpgpu_dualapprox/examples//scratch/test.mps")

    debug("Objective value: ", getobjectivevalue(m))
    #println("x = ", getvalue(x))

    Dict("status"=> status, "model" => m, "x" => x, "stats" => Dict("nb_free_var" => total_nb_var) )
end


function create_instance_solution(instance, sol_hash)
    ret_hash = Dict()

    N = instance["meta"]["n"]
    Q = 7

    ret_hash["solve_time"] = 0.0
    ret_hash["task_hash"] = Dict()
    ret_hash["work"] = getobjectivevalue(sol_hash["model"])

    x = getvalue(sol_hash["x"])

#    println("x:", x)

    for i in 1:N
        for j in 1:Q
#            if x[i,j] == 1.0
            # it can only be 0 or 1 (but Gurobi sometimes return 0.9999676)
            if x[i,j] > 0.0
                ret_hash["task_hash"][string(i)] = string(j)
                j = Q+1
            end
        end
    end

    ret_hash
end

function has_solution_for_lambda(mip_instance::Dict, lambda::Float64)
    sol = solve_problem_instance(mip_instance, lambda)
    has_sol = false

    status = sol["status"]

    if status == :Optimal
        work = getobjectivevalue(sol["model"])
        # need to check whether condition is met (work <= lambda * m)
        if work > lambda * float(mip_instance["meta"]["m"])
            has_sol = false
        else
            has_sol = true
        end
    end

    if has_sol == true
      return Dict("has_solution" => has_sol, "stats" => sol["stats"] )
    else
      return Dict("has_solution" => has_sol, "stats" => Dict() )
    end
end



function test_schedule_solver()

# read_solve_write_for_lambda(
# "/Users/sascha/programming/university/gpgpu_dualapprox/examples/input/input_instance_test.in",
# "/Users/sascha/programming/university/gpgpu_dualapprox/examples/scratch/testj_sol.json",
# 100)

lambda = 60.0
infile = "/Users/sascha/programming/university/gpgpu_dualapprox/examples/input/input_instance_test.in"
instance = SchedulerInput(JSON.parsefile(infile))

res = has_solution_for_lambda(instance, lambda)

@printf("solution for %f? %d\n", lambda, res)

#asolv.solve_and_write_solution(lambda, "/Users/sascha/programming/university/gpgpu_dualapprox/examples/scratch/testj_sol.json")

end
