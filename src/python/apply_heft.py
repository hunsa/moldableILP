#! /usr/bin/env python

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


import sys
import os
import yaml
import approx_common
import time

from optparse import OptionParser
from schedule_common import Core, GPU, MoldSchedule, TaskRect

in_data = None
seq_only = False

def get_parallel_time_cpu(task_str):
    global in_data
    global seq_only

    if seq_only:
        ptime = in_data["cpudata"][task_str][0]
    else:
        ptime = min(in_data["cpudata"][task_str])

    return ptime


def get_time_gpu(task_str):
    global in_data
    return in_data["gpudata"][task_str]

def lpt_first(a, b):
    global in_data

    cpu_a = get_parallel_time_cpu(a)
    gpu_a = get_time_gpu(a)
    #max_a = max(cpu_a, gpu_a)
    max_a = min(cpu_a, gpu_a)

    cpu_b = get_parallel_time_cpu(b)
    gpu_b = get_time_gpu(b)
    #max_b = max(cpu_b, gpu_b)
    max_b = min(cpu_b, gpu_b)

    if max_a - max_b < 0:
        ret = 1
    elif max_a - max_b > 0:
        ret = -1
    else:
        ret = 0

    return ret

def largest_ratio_first(a, b):
    global in_data

    ret = 0

    cpu_a = get_parallel_time_cpu(a)
    gpu_a = get_time_gpu(a)
    ratio_a = cpu_a / gpu_a

    cpu_b = get_parallel_time_cpu(b)
    gpu_b = get_time_gpu(b)
    ratio_b = cpu_b / gpu_b

    if ratio_a - ratio_b < 0:
        ret = 1
    elif ratio_a - ratio_b > 0:
        ret = -1
    else:
        ret = 0

    return ret


def build_heft_schedule(input_data, sequential_only, prio, jedfile, csvfile=None):
    global in_data
    global seqonly

    in_data = input_data
    seq_only = sequential_only

    approx_common.init_system()

    start_time = time.clock()

    nb_tasks = int(input_data["meta"]["n"])
    Core.nb_pus = int(input_data["meta"]["m"])
    GPU.nb_pus = int(input_data["meta"]["k"])

    # gimme m cores and k GPUs
    cores = [ Core(i) for i in xrange(0, Core.nb_pus) ]
    gpus  = [ GPU(i) for i in xrange(0, GPU.nb_pus) ]

    schedule = MoldSchedule(Core.nb_pus, GPU.nb_pus)

    task_id_list = []
    for i in xrange(0, nb_tasks):
        task_id = approx_common.get_task_str(i+1)
        task_id_list.append(task_id)

    if approx_common.debug == 1:
        print "unsorted:", task_id_list

    if prio != None:
        if prio == "lpt":
            task_id_list.sort(cmp=lpt_first)
        elif prio == "spt":
            task_id_list.sort(cmp=lpt_first)
            task_id_list.reverse()
        elif prio == "ratio":
            task_id_list.sort(cmp=largest_ratio_first)
        else:
            print >> sys.stderr, "unknown prio option:", prio
    else:
        prio = "lpt"

    if approx_common.debug == 1:
        print "sorted:", task_id_list

    if approx_common.debug == 1:
        if prio == "ratio":
            for i in xrange(0, nb_tasks):
                task_id = approx_common.get_task_str(i+1)
                cpu_a = get_parallel_time_cpu(task_id)
                gpu_a = get_time_gpu(task_id)
                ratio_a = cpu_a / gpu_a
                print "task", task_id, "ratio:", ratio_a

    for task_id in task_id_list:

        task_idx = task_id.replace("t", "")

        if approx_common.debug == 1:
            print "scheduling", task_id
        chosen_device_id = 0

        selected_core_idx = 0
        selected_nb_cores = Core.nb_pus
        eft_best = sys.float_info.max

        if seq_only:

            selected_nb_cores = 1

            for core_idx in xrange(0, Core.nb_pus):
                eft_core = cores[core_idx].get_lasttime() + input_data["cpudata"][task_id][0]
                if eft_core < eft_best:
                    eft_best = eft_core
                    selected_core_idx = core_idx

        else:
            eft_best = cores[0].get_lasttime() + input_data["cpudata"][task_id][Core.nb_pus-1]

        if approx_common.debug == 1:
            print "eft cpu", eft_best

        for gpu_id in xrange(0, GPU.nb_pus):
            device_id = gpu_id + 1
            eft_current = gpus[gpu_id].get_lasttime() + input_data["gpudata"][task_id]
            if approx_common.debug == 1:
                print "eft gpu", gpu_id, " : ", eft_current
            if eft_current < eft_best:
                chosen_device_id = device_id
                eft_best = eft_current

        if chosen_device_id == 0:

            if seq_only:

                task_start_time = cores[selected_core_idx].get_lasttime()
                task_end_time   = eft_best

                cores[selected_core_idx].set_lasttime(eft_best)

            else:

                task_start_time = cores[0].get_lasttime()
                task_end_time   = eft_best

                for core in cores:
                    core.set_lasttime(eft_best)

            # 0 in 3rd means nothing (simply a computation)
            task_rect = TaskRect(task_idx, Core.arch_id, 0)
            task_rect.set_procs([(selected_core_idx, selected_nb_cores)])
            task_rect.set_times(task_start_time, task_end_time)

            schedule.add_task_rect(task_rect)

        else:

            task_start_time = gpus[chosen_device_id-1].get_lasttime()
            task_end_time   = eft_best

            gpus[chosen_device_id-1].set_lasttime(eft_best)

            # 0 in 3rd means nothing (simply a computation)
            task_rect = TaskRect(task_idx, GPU.arch_id, 0)
            task_rect.set_procs([(chosen_device_id-1, 1)])
            task_rect.set_times(task_start_time, task_end_time)

            schedule.add_task_rect(task_rect)

    end_time = time.clock()

    if jedfile != None and jedfile != "":
        approx_common.write_jedfile(jedfile, schedule)

    if csvfile != None and csvfile != "":
        approx_common.write_csv_output(csvfile, schedule)

    print "total_solve_time:", (end_time-start_time)
    print "prio:", prio
    print "seq_only: %d" % ( int(seq_only) )

    makespan = schedule.get_makespan()
    print "makespan:", makespan

    sys.stdout.flush()

if __name__ == "__main__":


    if not os.environ.has_key("DUALAPPROX_HOME"):
        print >> sys.stderr, "set environment variable DUALAPPROX_HOME"
        sys.exit(1)

    parser = OptionParser( usage = "usage: %prog [options]" )

    parser.add_option( "-i", "--input",
                       action  = "store",
                       dest    = "ininst",
                       type    = "string",
                       help    = "file with input data" )

    parser.add_option( "-j", "--jedule",
                       action  = "store",
                       dest    = "jedfile",
                       type    = "string",
                       help    = "file name for jedule output" )

    parser.add_option( "-p", "--priorization",
                       action  = "store",
                       dest    = "prio",
                       type    = "string",
                       help    = "priorization option (lpt, spt, ratio CPU/GPU)" )

    parser.add_option( "-s", "--sequential",
                       action  = "store_true",
                       dest    = "seqonly",
                       help    = "sequential processing only",
                       default = False )

    ( options, args ) = parser.parse_args()

    if options.ininst == None or not os.path.exists(options.ininst):
        print >> sys.stderr, "input file invalid"
        parser.print_help()
        sys.exit(1)

    fh = open(options.ininst)
    input_content = fh.readlines()
    fh.close()
    input_content = "".join(input_content)

    input_data = yaml.load(input_content)

    build_heft_schedule(input_data, options.prio, options.seqonly, options.jedule)
