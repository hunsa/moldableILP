###############################################################################
# SCHEDULING INDEPENDENT MOLDABLE TASKS ON MULTI-CORES WITH GPUS
# Copyright (C) 2014 Sascha Hunold <sascha@hunoldscience.net>
# Raphaël Bleuse <raphael.bleuse@imag.fr>
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

include("approx_common.jl")
include("jedule_output.jl")
include("output_csv.jl")

stats = Dict()

abstract PU

type CPU <: PU
  archtype::Int
  pid::Int
  lasttime::Float64
end

type GPU <: PU
  archtype::Int
  pid::Int
  lasttime::Float64
end

function Base.show(io::IO, cpu::CPU)
    print(io, "CPU: $(cpu.archtype), $(cpu.pid), $(cpu.lasttime)")
end

function get_task_efficiency(instance::SchedulerInput, lambda::Float64, task_str::AbstractString)
  nb_cpu = get_procs_by_lambda(instance, task_str, lambda)
  cpu_time = get_time_by_procs(instance, task_str, nb_cpu)
  gpu_time = float(instance["gpudata"][task_str])
  ratio = cpu_time / gpu_time
  return ratio
end

function get_task_gputime(instance::SchedulerInput, task_str::AbstractString)
  gpu_time = float(instance["gpudata"][task_str])
  return gpu_time
end

function get_task_canonical_core_count(instance::SchedulerInput,  lambda::Float64, task_str::AbstractString)
  nb_cpu = get_procs_by_lambda(instance, task_str, lambda)
  return nb_cpu
end

# function spt_comparator(task1_str::String, task2_str::String, instance::SchedulerInput)
#   gpu_time1 = instance["gpudata"][task1_str]
#   gpu_time2 = instance["gpudata"][task2_str]
#   return gpu_time1 - gpu_time2
# end

function partition_cores(cores::Array{CPU})

  partitions = Array{CPU}[]

  debug("unsorted cores: ", cores)
  sort!(cores, by=f(x)=x.pid)
  debug("sorted cores: ", cores)

  start_idx = 1
  end_idx = 1
  cur_idx = 2
  while cur_idx <= length(cores)
    if cores[end_idx].pid == cores[cur_idx].pid - 1
      end_idx = cur_idx
      cur_idx += 1
    else
      part = cores[start_idx:end_idx]
      push!(partitions, part)

#      println(part)
      start_idx = cur_idx
      end_idx   = cur_idx
      cur_idx   += 1
#      println(start_idx, " ", end_idx, " ", cur_idx)
    end
  end

  part = cores[start_idx:end_idx]
  push!(partitions, part)
#  println(part)

  partitions
end

function solve_problem_2approx(instance::SchedulerInput,
                               inst_params::ScheduleInstanceParams)

    N = Int(instance["meta"]["n"])
    M = Int(instance["meta"]["m"])
    K = Int(instance["meta"]["k"])

    lb = compute_lowerbound(instance)
    ub = compute_upperbound(instance)

#    println(lb)
#    println(ub)

    params = Dict()

    upper = ub
    lower = lb

    best_lambda = -1.0
    best_schedule = ScheduleRect[]

    empty!(stats)
    stats["nb_of_iterations"] = 0
    stats["mean_solve_time"]  = 0.0
    stats["total_solve_time"] = 0.0

    start_time = time_ns()

    while upper/lower > getCutoffRatio()

      task_id_hybrid_lst = AbstractString[]
      task_id_cpu_lst = AbstractString[]
      task_id_gpu_lst = AbstractString[]

      schedule = ScheduleRect[]

      bisect = lower + (upper-lower)/2.0
      lambda = bisect

      debug("lb=", lb)
      debug("ub=", ub)
      debug("lambda=", bisect)

      queue_cores = Collections.PriorityQueue()
      queue_gpus  = Collections.PriorityQueue()

      cpus = CPU[]
      gpus = GPU[]
      for i = 1:M
        cpu = CPU(0, i, 0.0)
        push!(cpus, cpu)
        Collections.enqueue!(queue_cores, cpu, cpu.lasttime)
      end

      for k = 1:K
        gpu = GPU(1, k, 0.0)
        push!(gpus, gpu)
        Collections.enqueue!(queue_gpus, gpu, gpu.lasttime)
      end

#      ihelper = InstanceHelper(instance, bisect)


      for i = 1:N
        task_str = get_task_str(i)

        gpu_time = float( instance["gpudata"][task_str] )
        canonical_nb_cpu = get_procs_by_lambda(instance, task_str, bisect)

        if gpu_time > bisect && canonical_nb_cpu > M
          lower = bisect
          @goto iter_end
        elseif gpu_time > bisect
          push!(task_id_cpu_lst, task_str)
        elseif canonical_nb_cpu > M
          push!(task_id_gpu_lst, task_str)
        else
          push!(task_id_hybrid_lst, task_str)
        end
      end

#      debug("cpu only: " * reduce(*, map(x -> x * " ", task_id_cpu_lst)))
      debug("cpu only: ", task_id_cpu_lst)
      debug("gpu only: ", task_id_gpu_lst)
      debug("hybrid  : ", task_id_hybrid_lst)

      task_id_gpu_lst    = sort(task_id_gpu_lst, by=f(x)=get_task_gputime(instance, x))
      task_id_hybrid_lst = sort(task_id_hybrid_lst, by=f(x)=get_task_efficiency(instance, lambda, x))

      debug("sorted gpu only: ", task_id_gpu_lst)
      debug("sorted hybrid  : ", task_id_hybrid_lst)

      cur_gpu_work = 0.0

      while( (length(task_id_gpu_lst) > 0) && (cur_gpu_work <= bisect * K) )

        # schedule task on least loaded GPU
        cur_gpu = Collections.dequeue!(queue_gpus)
        cur_task_str  = pop!(task_id_gpu_lst)
        cur_starttime = cur_gpu.lasttime
        cur_gpu.lasttime += get_task_gputime(instance, cur_task_str)
        cur_endtime = cur_gpu.lasttime
        cur_gpu_work += get_task_gputime(instance, cur_task_str)

        # add task to schedule
        srect = ScheduleRect(get_task_id(cur_task_str), cur_gpu.archtype, cur_gpu.pid, 1, cur_starttime, cur_endtime)
        push!(schedule, srect)

        Collections.enqueue!(queue_gpus, cur_gpu, cur_gpu.lasttime)
      end

      if length(task_id_gpu_lst) > 0
        # some GPU task could not be scheduled
        lower = bisect
        @goto iter_end
      end

      # same as above with hybrid tasks, we do not check for remaining,
      # it'll be done while trying to schedule them on CPUs
      while( (length(task_id_hybrid_lst) > 0) && (cur_gpu_work <= bisect * K) )
        cur_task_str  = pop!(task_id_hybrid_lst)
        cur_gpu = Collections.dequeue!(queue_gpus)

        cur_starttime = cur_gpu.lasttime
        cur_gpu.lasttime += get_task_gputime(instance, cur_task_str)
        cur_endtime = cur_gpu.lasttime
        cur_gpu_work += get_task_gputime(instance, cur_task_str)

        # actually schedule task
        srect = ScheduleRect(get_task_id(cur_task_str), cur_gpu.archtype, cur_gpu.pid, 1, cur_starttime, cur_endtime)
        push!(schedule, srect)

        # push back current gpu in future available resources
        Collections.enqueue!(queue_gpus, cur_gpu, cur_gpu.lasttime)
      end

#      print(task_id_cpu_lst)
#      print(task_id_hybrid_lst)
      task_id_remaining = append!(task_id_cpu_lst, task_id_hybrid_lst)
      task_id_remaining = sort(task_id_remaining, by=f(x)=get_task_canonical_core_count(instance, lambda, x))

      debug("remaining tasks: ", task_id_remaining)

      while( length(task_id_remaining) > 0)
        cur_task_str  = pop!(task_id_remaining)

        cur_nb_cores = get_task_canonical_core_count(instance, lambda, cur_task_str)

        cur_cores = CPU[]
        for i in 1:cur_nb_cores
          push!( cur_cores, Collections.dequeue!(queue_cores) )
        end
        cur_starttime = cur_cores[cur_nb_cores].lasttime
        cur_endtime   = cur_starttime + get_time_by_procs(instance, cur_task_str, cur_nb_cores)

        if cur_endtime > 2 * bisect
          lower = bisect
          @goto iter_end
        end

        for i in 1:cur_nb_cores
          cur_cores[i].lasttime = cur_endtime
          Collections.enqueue!(queue_cores, cur_cores[i], cur_cores[i].lasttime)
        end

#        @printf "type of cores : %s" typeof(cur_cores)
        partitioned_cores = partition_cores(cur_cores)

        debug("task: ", cur_task_str)
        for i = 1:length(partitioned_cores)
          debug("partition ", i, ": r", partitioned_cores[i])

          partition = partitioned_cores[i]
          first_pid = partition[1].pid
          nb_p      = length(partition)

          # actually schedule task
          srect = ScheduleRect(get_task_id(cur_task_str), partition[1].archtype, first_pid, nb_p, cur_starttime, cur_endtime)
          push!(schedule, srect)
        end

      end

      upper = bisect
      best_lambda = bisect
      best_schedule = schedule

    @label iter_end
      stats["nb_of_iterations"] += 1
    end

    end_time = time_ns()

    stats["total_solve_time"] = (end_time-start_time)/1e9
    stats["mean_solve_time"]  = stats["total_solve_time"] / stats["nb_of_iterations"]

    Base.isless(x::ScheduleRect,y::ScheduleRect) = x.etime < y.etime
    cmax = maximum(best_schedule).etime

    @printf "best lambda: %f\n" best_lambda

    for key in keys(stats)
      @printf("%s: %s\n", key, stats[key])
    end

    @printf "bound: %f\n" (2*best_lambda)
    @printf "makespan: %f\n" cmax

    if inst_params.jedfile != ""
      write_jedule_output(instance, best_schedule, inst_params.jedfile)
    end
    if inst_params.csvfile != ""
      write_csv_output(instance, best_schedule, inst_params.csvfile)
    end
end


#Logging.configure(level=DEBUG)
#Logging.configure(level=INFO)

function test_2approx()

  #infile = "/Users/sascha/work/progs/perfpack/task_sched/2015-01-imts/000-test_small_instances_opt-2015-01-12-1710/02-exp/input/instances/problem_n10_m8_k2_i0.in"
  infile = "/Users/sascha/work/progs/perfpack/task_sched/2016/000-sched_julia_lpt_changed-2016-03-09-1307/02-exp/input/instances/problem_n10_m4_k2_i9.in.bz2"
  #infile = "/Users/sascha/work/progs/perfpack/task_sched/2016/000-sched_julia_lpt_changed-2016-03-09-1307/02-exp/input/instances/problem_n1000_m512_k32_i6.in.bz2"

  instance = load_scheduling_instance(infile)

  solve_problem_2approx(
      #"/Users/sascha/work/progs/perfpack/task_sched/2015-01-imts/000-test_small_instances_opt-2015-01-12-1710/02-exp/input/instances/problem_n10_m8_k2_i1.in",
      instance,
      "/Users/sascha/tmp/approxsched/julia.out",
      "/Users/sascha/tmp/approxsched/julia.jed",
      "/Users/sascha/tmp/approxsched/julia.csv"
      )

end
