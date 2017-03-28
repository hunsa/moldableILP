
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

from jinja2 import Environment, FileSystemLoader
import os


class PU:
    arch_id = None
    nb_pus = None # number of PU of this specific architecture

    def __init__(self, pid):
        self.pid = pid
        self.lasttime = 0.0

    def get_pid(self):
        return self.pid

    def get_lasttime(self):
        return self.lasttime

    def set_lasttime(self, time):
        self.lasttime = time


class Core(PU):
    arch_id = 0


class GPU(PU):
    arch_id = 1


class MoldSchedule:

    def __init__(self, nb_cpu, nb_gpu):
        self.task_rects = []
        self.nb_cpu = nb_cpu
        self.nb_gpu = nb_gpu
        self.metainfo = {}
        self.archs = [Core, GPU]

    def get_nb_cpu(self):
        return self.nb_cpu

    def get_nb_gpu(self):
        return self.nb_gpu

    def add_task_rect(self, task_rect):
        self.task_rects.append(task_rect)

    def get_task_rects(self):
        return self.task_rects

    def get_makespan(self):
        makespan = 0.0
        for task_rect in self.task_rects:
            makespan = max(makespan, task_rect.get_end_time())
        return makespan

    def set_metainfo(self, key, value):
        self.metainfo[key] = value

    def get_metainfo(self, key):
        return self.metainfo[key]

    def get_jedule_output(self):
        template_dir = os.path.dirname(os.path.abspath(__file__))
        j2_env = Environment(
            loader=FileSystemLoader(template_dir),
            trim_blocks=True,
            lstrip_blocks=True
        )
        template = j2_env.get_template('jinja.jed')
        return template.stream(vars(self))

    def write_csv_output(self, fname):
        fh = open(fname, "w")
        fh.write("name;type;setid;sres;nres;stime;etime\n")
        for tr in self.task_rects:
            for blk_start, blk_size in tr.resources:
                fh.write("%s;%d;%d;%d;%d;%f;%f\n" % (
                tr.task_id, \
                tr.device_id, \
                tr.set_id,
                blk_start, \
                blk_size, \
                tr.start_time, \
                tr.end_time )
                )

        fh.close()



class TaskRect:

    def __init__(self, task_id, device_id, set_id):
        self.task_id = task_id
        self.device_id = device_id
        self.set_id = set_id
        self.resources = [] # list of contiguous blocks: (start_id, nb_procs)
        self.start_time = None
        self.end_time = None

    def get_task_id(self):
        return self.task_id

    def get_device_id(self):
        return self.device_id

    def get_set_id(self):
        return self.set_id

    def get_set_str(self):
        return self.set_id

    def get_nbp(self):
        # TODO: could be cached or computed when pus are added
        return reduce(lambda x, y: x + y, [ r[1] for r in self.resources ])

    def get_start_time(self):
        return self.start_time

    def get_end_time(self):
        return self.end_time

    def set_procs(self, resources):
        self.resources = resources

    def set_times(self, start_time, end_time):
        self.start_time = start_time
        self.end_time = end_time

    def print_rect(self):
        print "*********************************************"
        print "task id", self.task_id, " device:", self.device_id
        print "set_id", self.set_id
        print "resources (start_id, nb_pus)", self.resources
        print "start:", self.start_time
        print "end  :", self.end_time

class ImtsTaskRect(TaskRect):

    def __init__(self, task_id, device_id, set_id):
        TaskRect.__init__(self, task_id, device_id, int(set_id)-1)

    def get_set_str(self):
        return "set%d" % ( self.set_id )
