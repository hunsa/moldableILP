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

include("output_common.jl")

function write_csv_output(instance, rect_list, csvfile_name)
    fh = open(csvfile_name, "w")

    write(fh,
"""
name;type;sres;nres;stime;etime
""")

    for i=1:length(rect_list)
        rect = rect_list[i]

       write(fh,
"""
$(rect.task_id);$(rect.device_id);$(rect.start_idx-1);$(rect.nb_p);$(rect.stime);$(rect.etime)
""")

    end

    close(fh)
end
