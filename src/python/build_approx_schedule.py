#! /usr/bin/env python

# SCHEDULING INDEPENDENT MOLDABLE TASKS ON MULTI-CORES WITH GPUS
# Copyright (C) 2014 Sascha Hunold <sascha@hunoldscience.net>
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

import sys
import os
import yaml
import approx_common

from optparse import OptionParser
from schedule_common import Core, GPU, MoldSchedule, ImtsTaskRect

def try_whether_seq_task_fits( core, cpudata, task_id, bound ):
    fits = 0

    task_str = approx_common.get_task_str(task_id)
    seq_time = cpudata[task_str][0]

    if core.get_lasttime() + seq_time <= bound:
        fits = 1
    else:
        fits = 0

    return fits

def schedule_seq_task( schedule, core, cpudata, task_id, set_id):

    task_str = approx_common.get_task_str(task_id)

    seq_time = cpudata[task_str][0]

    task_start_time = core.get_lasttime()
    task_end_time   = core.get_lasttime() + seq_time

    core.set_lasttime(task_end_time)
    if approx_common.debug == 1:
        print ">>>> core.pid:", core.get_pid()
    task_rect = ImtsTaskRect(task_id, Core.arch_id, set_id)
    task_rect.set_procs([(core.get_pid(), 1)])
    task_rect.set_times(task_start_time, task_end_time)

    schedule.add_task_rect(task_rect)

def schedule_par_task(schedule, core_id, task_np, cores, cpudata, task_id, set_id):
    task_str = approx_common.get_task_str(task_id)
    task_time = approx_common.get_time_by_procs(cpudata, task_str, task_np)

    min_start_time = 0.0
    for core in cores[core_id:core_id+task_np]:
        if core.get_lasttime() > min_start_time:
            min_start_time = core.get_lasttime()

    task_start_time = min_start_time
    task_end_time   = min_start_time + task_time

    for core in cores[core_id:core_id+task_np]:
        core.set_lasttime(task_end_time)

    task_rect = ImtsTaskRect(task_id, Core.arch_id, set_id)
    task_rect.set_procs([(cores[core_id].get_pid(), task_np)])
    task_rect.set_times(task_start_time, task_end_time)

    schedule.add_task_rect(task_rect)


def schedule_gpu_task( schedule, gpu, gpudata, task_id, set_id):

    task_str = approx_common.get_task_str(task_id)

    gputime = gpudata[task_str]

    task_start_time = gpu.get_lasttime()
    task_end_time   = gpu.get_lasttime() + gputime

    gpu.set_lasttime(task_end_time)
    if approx_common.debug == 1:
        print ">>>> gpu.id:", gpu.get_pid()
    task_rect = ImtsTaskRect(task_id, GPU.arch_id, set_id)
    task_rect.set_procs([(gpu.pid, 1)])
    task_rect.set_times(task_start_time, task_end_time)

    schedule.add_task_rect(task_rect)

def get_taskids_of_set(solution_data, set_id):
    set_tasks = []
    for task_id in solution_data["task_hash"].keys():
        if solution_data["task_hash"][task_id] == set_id:
            set_tasks.append(task_id)
    return set_tasks

def get_next_free_core_idx(cores):
    idx = -1
    for core_idx in xrange(0, len(cores)):
        if cores[core_idx].get_lasttime() == 0.0:
            idx = core_idx
            break
    return idx

def lpt_sort_seq_cpu_tasks(task_set, cpudata):
    tl = []
    for task_id in task_set:
        task_str = approx_common.get_task_str(task_id)
        seq_time = cpudata[task_str][0]
        tl.append( (task_id, seq_time) )
    tl = sorted(tl, key=lambda item: item[1], reverse=True)

    lpt_set2 = []
    for item in tl:
        lpt_set2.append(item[0])

    return lpt_set2

def lpt_sort_cpu_tasks_set2(task_set, cpudata):
    tl = []
    for task_id in task_set:
        task_str = approx_common.get_task_str(task_id)
        seq_time = cpudata[task_str][0]
        tl.append( (task_id, seq_time) )

    tl = sorted(tl, key=lambda item: item[1])

    tllpt = []
    while tl:
        tllpt.append(tl.pop())
        if (len(tl) == 0):
            break;
        tllpt.append(tl.pop(0))

    lpt_set2 = []
    for item in tllpt:
        lpt_set2.append(item[0])

    return lpt_set2


def lpt_sort_gpu_tasks(task_set, gpudata):
    tl = []
    for task_id in task_set:
        task_str = approx_common.get_task_str(task_id)
        seq_time = gpudata[task_str]
        tl.append( (task_id, seq_time) )
    tl = sorted(tl, key=lambda item: item[1], reverse=True)

    lpt_set2 = []
    for item in tl:
        lpt_set2.append(item[0])

    return lpt_set2


def build_schedule(input_data, solution_data, lambval, jedfile, csvfile=None):

    # set 1-7 (in paper 0-6)
    # 1: < 1/2 lambda   -> sequential
    # 2: >= 1/2 lambda and <= 3/4 lambda  -> sequential
    # 3: > lambda and <= 3/2 lambda  -> moldable <= 3/2 lambda
    # 4: > 1/2 lambda and <= lambda -> moldable <= lambda
    # 5: <= 1/2 lambda -> moldable <= 1/2 lambda
    # 6: > 1/2 lambda and <= lambda -> GPU
    # 7: <= 1/2 lambda -> GPU

    # first check whether solution is correct
    sol_work = float(solution_data["work"])
    if approx_common.debug == 1:
        print "sol_work:", sol_work

    # work should be <= lambda * m
    if approx_common.debug == 1:
        print "lambda * m :", float(lambval) * float(input_data["meta"]["m"])
    if sol_work > float(lambval) * float(input_data["meta"]["m"]):
        print >> sys.stderr, "solution invalid (> lambda * m)"
        sys.exit(1)

    if approx_common.debug == 1:
        for task_id in solution_data["task_hash"].keys():
            print task_id, " -> set", solution_data["task_hash"][task_id]

    nb_tasks = int(input_data["meta"]["n"])
    Core.nb_pus = int(input_data["meta"]["m"])
    GPU.nb_pus = int(input_data["meta"]["k"])

    approx_bound = 3.0/2.0 * float(lambval)

    # gimme m cores and k GPUs
    cores = [ Core(i) for i in xrange(0, Core.nb_pus) ]
    gpus  = [ GPU(i) for i in xrange(0, GPU.nb_pus) ]

    schedule = MoldSchedule(Core.nb_pus, GPU.nb_pus)

    schedule.set_metainfo("lambda", lambval)

    ##################
    ###### CPU #######
    ##################

    # schedule tasks from set 2 (set 1 in paper)
    # can schedule two tasks right after each other

    set_2_tasks_unsorted = get_taskids_of_set(solution_data, "2")
    set_2_tasks = lpt_sort_cpu_tasks_set2(set_2_tasks_unsorted, input_data["cpudata"])

    #print "set2, unsorted: ", set_2_tasks_unsorted
    #print "set2, sorted  : ", set_2_tasks

    if approx_common.debug == 1:
        print "set 2 tasks:", set_2_tasks
    # these tasks are sequential
    task_pos = 0
    core_id  = 0
    while task_pos + 1 < len(set_2_tasks):
        schedule_seq_task( schedule, cores[core_id], input_data["cpudata"], set_2_tasks[task_pos], "2")
        schedule_seq_task( schedule, cores[core_id], input_data["cpudata"], set_2_tasks[task_pos+1], "2")
        core_id += 1
        task_pos += 2

    #print task_pos, len(set_2_tasks)
    if task_pos < len(set_2_tasks):
        schedule_seq_task( schedule, cores[core_id], input_data["cpudata"], set_2_tasks[task_pos], "2")

    nb_core_with_two_tasks_set2 = len(set_2_tasks) / 2
    nb_core_with_one_task_set2  = len(set_2_tasks) % 2

    # now schedule large moldable tasks from set 3 (paper set 2)
    set_3_tasks = get_taskids_of_set(solution_data, "3")
    if approx_common.debug == 1:
        print "set 3 tasks:", set_3_tasks
    set_3_tasks_to_schedule = set_3_tasks[:]
    core_id = get_next_free_core_idx(cores)
    while len(set_3_tasks_to_schedule) > 0:
        mtask_id = set_3_tasks_to_schedule.pop(0)
        mtask_str = approx_common.get_task_str(mtask_id)
        mtask_procs = approx_common.get_procs_by_lambda(input_data["cpudata"], mtask_str, 3 * float(lambval) / 2)
        schedule_par_task(schedule, core_id, mtask_procs, cores, input_data["cpudata"], mtask_id, "3")
        core_id = core_id + mtask_procs

    # now schedule moldable tasks from set 4 (paper set 3)
    set_4_tasks = get_taskids_of_set(solution_data, "4")
    if approx_common.debug == 1:
        print "set 4 tasks:", set_4_tasks
    set_4_tasks_to_schedule = set_4_tasks[:]
    core_set_4_start_idx = get_next_free_core_idx(cores)
    core_set_4_idx = core_set_4_start_idx
    while len(set_4_tasks_to_schedule) > 0:
        mtask_id = set_4_tasks_to_schedule.pop(0)
        mtask_str = approx_common.get_task_str(mtask_id)
        mtask_procs = approx_common.get_procs_by_lambda(input_data["cpudata"], mtask_str, float(lambval) )
        schedule_par_task(schedule, core_set_4_idx, mtask_procs, cores, input_data["cpudata"], mtask_id, "4")
        core_set_4_idx += mtask_procs

    # now schedule (back-filling) moldable tasks from set 5 (paper set 4)
    # fill behind tasks from set 4
    set_5_tasks = get_taskids_of_set(solution_data, "5")
    if approx_common.debug == 1:
        print "set 5 tasks:", set_5_tasks
    set_5_tasks_to_schedule = set_5_tasks[:]
    core_set_5_idx = core_set_4_start_idx
    while len(set_5_tasks_to_schedule) > 0:
        mtask_id = set_5_tasks_to_schedule.pop(0)
        mtask_str = approx_common.get_task_str(mtask_id)
        mtask_procs = approx_common.get_procs_by_lambda(input_data["cpudata"], mtask_str, float(lambval) / 2 )
        schedule_par_task(schedule, core_set_5_idx, mtask_procs, cores, input_data["cpudata"], mtask_id, "5")
        core_set_5_idx += mtask_procs

    # backfill all set 1 tasks from 0 -> m-1 (paper => set 0)
    set_1_tasks = get_taskids_of_set(solution_data, "1")
    if approx_common.debug == 1:
        print "set 1 tasks:", set_1_tasks


    set_1_tasks_to_schedule = set_1_tasks[:]
    set_1_tasks_to_schedule = lpt_sort_seq_cpu_tasks(set_1_tasks_to_schedule, input_data["cpudata"])

    while len(set_1_tasks_to_schedule) > 0:

        task_id = set_1_tasks_to_schedule[0]
        task_str = approx_common.get_task_str(task_id)

        found_core_id = -1
        eft_best = -1
        for cid in xrange(0, Core.nb_pus):

            eft_core = cores[cid].get_lasttime() + input_data["cpudata"][task_str][0]
            if eft_core <= approx_bound:
                if eft_best == -1:
                    eft_best = eft_core
                    found_core_id = cid
                elif eft_best > eft_core:
                    eft_best = eft_core
                    found_core_id = cid

        if found_core_id != -1:
            schedule_seq_task(schedule, cores[found_core_id], input_data["cpudata"], set_1_tasks_to_schedule[0], "1")
            set_1_tasks_to_schedule.pop(0)
        else:
            print >> sys.stderr, "cannot schedule task", task_id, "(does nowhere fit)"
            raise RuntimeError

    ##################
    ###### GPU #######
    ##################

    # only GPU tasks available
    set_6_tasks = get_taskids_of_set(solution_data, "6")
    if approx_common.debug == 1:
        print "set 6 tasks:", set_6_tasks

    gpu_id = 0
    # schedule each of these tasks on one GPU
    set_6_to_schedule = set_6_tasks[:]
    while len(set_6_to_schedule) > 0:
        schedule_gpu_task(schedule, gpus[gpu_id], input_data["gpudata"], set_6_to_schedule[0], "6")
        set_6_to_schedule.pop(0)
        gpu_id += 1

    # now fill remaining GPU tasks behind tasks from set 6
    set_7_tasks = get_taskids_of_set(solution_data, "7")
    if approx_common.debug == 1:
        print "set 7 tasks:", set_7_tasks
    set_7_to_schedule = set_7_tasks[:]


    #print "set7, unsorted: ", set_7_to_schedule
    set_7_to_schedule = lpt_sort_gpu_tasks(set_7_to_schedule, input_data["gpudata"])
    #print "set7, sorted  : ", set_7_to_schedule

    # we do the same best eft approach as for the core tasks
    while len(set_7_to_schedule) > 0:

        task_id = set_7_to_schedule[0]
        task_str = approx_common.get_task_str(task_id)

        found_gpu_id = -1
        eft_best = -1

        for gid in xrange(0, GPU.nb_pus):

            eft_gpu = gpus[gid].get_lasttime() + input_data["gpudata"][task_str]
            if eft_gpu <= approx_bound:
                if eft_best == -1:
                    eft_best = eft_gpu
                    found_gpu_id = gid
                elif eft_best > eft_gpu:
                    eft_best = eft_gpu
                    found_gpu_id = gid

        if found_gpu_id != -1:
            schedule_gpu_task(schedule, gpus[found_gpu_id], input_data["gpudata"], set_7_to_schedule[0], "7")
            set_7_to_schedule.pop(0)
        else:
            print >> sys.stderr, "cannot schedule GPU task", task_id, "(does nowhere fit)"
            raise RuntimeError

    makespan = 0.0
    for task_rect in schedule.get_task_rects():
        if makespan < task_rect.get_end_time():
            makespan = task_rect.get_end_time()
        if approx_common.debug == 1:
            task_rect.print_rect()

    if jedfile != None and jedfile != "":
        approx_common.write_jedfile(jedfile, schedule)

    if csvfile != None and csvfile != "":
        approx_common.write_csv_output(csvfile, schedule)

    # sanity check
    bound = 3 * float(lambval) / 2
    if makespan > bound:
        print "ATTENTION ! INVALID SOLUTION"
        print "makespan  : ", makespan
        print "3/2 lambda: ", bound

    if len(schedule.get_task_rects()) != nb_tasks:
        print "ATTENTION ! PROBLEM DETECTED"
        print "nb scheduled tasks: ", len(schedule.get_task_rects())
        print "nb tasks in prob. : ", nb_tasks


    print "bound:", bound
    print "makespan:", makespan

    sys.stdout.flush()

if __name__ == "__main__":

    parser = OptionParser( usage = "usage: %prog [options]" )

    parser.add_option( "-i", "--input",
                       action  = "store",
                       dest    = "ininst",
                       type    = "string",
                       help    = "file with input data" )

    parser.add_option( "-l", "--lambda",
                       action  = "store",
                       dest    = "lambval",
                       type    = "string",
                       help    = "lambda value" )

    parser.add_option( "-s", "--solution",
                       action  = "store",
                       dest    = "solfile",
                       type    = "string",
                       help    = "JSON file (with CPLEX/GLPK solution)" )

    parser.add_option( "-j", "--jedule",
                       action  = "store",
                       dest    = "jedfile",
                       type    = "string",
                       help    = "file name for jedule output" )

    ( options, args ) = parser.parse_args()

    if options.ininst == None or not os.path.exists(options.ininst):
        print >> sys.stderr, "input file invalid"
        parser.print_help()
        sys.exit(1)

    if options.lambval == None:
        print >> sys.stderr, "lambda invalid"
        parser.print_help()
        sys.exit(1)

    if options.solfile == None or not os.path.exists(options.solfile):
        print >> sys.stderr, "solfile (solution) invalid"
        parser.print_help()
        sys.exit(1)


    approx_common.init_system()

    fh = open(options.ininst)
    input_content = fh.readlines()
    fh.close()
    input_content = "".join(input_content)

    inputdata = yaml.load(input_content)

    fh = open(options.solfile)
    solution_content = fh.readlines()
    fh.close()
    solution_content = "".join(solution_content)

    solutiondata = yaml.load(solution_content)

    build_schedule(inputdata, solutiondata, options.lambval, options.jedfile)
