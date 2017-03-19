
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


import os
import yaml

# do not use, use environment
debug = 0

dual_approx_pathname = None

use_cplex = 0
#use_cplex = 1
#use_symphony = 0
use_symphony = 1

# when to stop bisection algorithm
# when upperbound/lowerbound <= cutoff_ratio
cutoff_ratio = 1.01

CPLEX_PATH="/Users/sascha/local/CPLEX_Studio125/cplex/bin/x86_darwin/cplex"
#CPLEX_PATH="/home/sascha/local/CPLEX_Studio1251/cplex/bin/x86-64_sles10_4.1/cplex"

#GLPSOL_PATH="glpsol"
#GLPSOL_PATH="/opt/local/bin/glpsol"
GLPSOL_PATH="/usr/bin/glpsol"

#SYMPHONY_PATH="symphony"
SYMPHONY_PATH="/usr/bin/symphony"


def init_system():
    global debug

    if os.environ.has_key("DUALAPPROX_DEBUG_LEVEL"):
        debug = int(os.environ.get("DUALAPPROX_DEBUG_LEVEL"))
    else:
        debug = 0

def get_approx_code_basename():
    global dual_approx_pathname
    if dual_approx_pathname == None:
        dual_approx_pathname = os.environ.get("DUALAPPROX_HOME")
    return dual_approx_pathname

def get_task_str(task_id):
    return "t%d" % ( int(task_id) )

def write_jedfile(fname, schedule):
    content = schedule.get_jedule_output()
    content.dump(fname)

def write_csv_output(fname, schedule):
    schedule.write_csv_output(fname)

def load_json_file(filename):
    fh = open(filename)
    file_content = fh.readlines()
    fh.close()
    content = "".join(file_content)
    data = yaml.load(content)
    return data


def get_procs_by_lambda(cpu_data_hash, task_str, h_bound):
    #ret_nb_procs = sys.maxint
    ret_nb_procs = 100000

    time_arr = cpu_data_hash[task_str]

#     if debug:
#         print time_arr
#         print "bound:", h_bound

    for i in xrange(0, len(time_arr) ):
        if float(time_arr[i]) <= h_bound:
            ret_nb_procs = i+1
            break

    return ret_nb_procs

def get_time_by_procs(cpu_data_hash, task_str, procs):
    return cpu_data_hash[task_str][procs-1]
