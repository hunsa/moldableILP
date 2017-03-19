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
import approx_common

from optparse import OptionParser

if __name__ == "__main__":

    if not os.environ.has_key("DUALAPPROX_HOME"):
        print >> sys.stderr, "set environment variable DUALAPPROX_HOME"
        sys.exit(1)

    parser = OptionParser( usage = "usage: %prog [options]" )

    parser.add_option( "-o", "--outdir",
                       action  = "store",
                       dest    = "outdir",
                       type    = "string",
                       help    = "directory for problem files" )

    ( options, args ) = parser.parse_args()

    rgen_script = os.path.join( approx_common.get_approx_code_basename(), "src", "R", "make_instance2.R" )

    if options.outdir == None or not os.path.exists(options.outdir):
        print >> sys.stderr, "outdir invalid"
        parser.print_help()
        sys.exit(1)

    #nlist = [ 10, 100, 1000 ]
    #nlist = [ 10, 50, 100 ]

    mlist = [ 4, 16, 64, 256, 512 ]
    klist = [ 1, 2, 4, 8, 16, 32 ]

    # factor 16 between max_m and max_k
    # max_k = max_m / 16
    nhash = {
        10 : {
        "min_m" : 4,
        "max_m" : 16,
        "max_k" : 1
        },
        100 : {
        "min_m" : 4,
        "max_m" : 64,
        "max_k" : 4
        },
        1000 : {
        "min_m" : 16,
        "max_m" : 512,
        "max_k" : 32
        }
    }


    sfrac_min = 0
    sfrac_max = .9
    gpu_min_factor = 0.1
    gpu_max_factor = 1.5
    gpu_mean_factor = 0.2
    gpu_sd_factor = 0.5
    min_seq_time = 1
    max_seq_time = 100

    nb_instances = 5

    for n in nhash.keys():
        for m in mlist:
            for k in klist:
                if m > nhash[n]["max_m"] or m < nhash[n]["min_m"] or k > nhash[n]["max_k"]:
                    continue

                for i in xrange(0, nb_instances):
                    fname = "problem_n%d_m%d_k%d_i%d.in" % ( n, m, k, i )
                    outpath = os.path.join( options.outdir, fname )
                    call = "Rscript %s -n %d -m %d -k %d -o %s -s %d" % ( rgen_script, n, m, k, outpath, i )
                    print call
                    os.system(call)
                    call = "bzip2 %s" % ( outpath )
                    os.system(call)
