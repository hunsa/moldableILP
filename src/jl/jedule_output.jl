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

function write_jedule_output(instance, rect_list, jedfile)
    fh = open(jedfile, "w")

    write(fh,
"""
<?xml version=\"1.0\"?>
<grid_schedule>
<meta_info>
</meta_info>
<grid_info>
""")

    write(fh, "<info name=\"nb_clusters\" value=\"$(1+instance["meta"]["k"])\"/>\n")

write(fh,
"""
<clusters>
""")

    write(fh, "<cluster id=\"0\" hosts=\"$(instance["meta"]["m"])\" first_host=\"0\"/>\n")
#    for k=1:int(instance["meta"]["k"])
    write(fh, "<cluster id=\"1\" hosts=\"$(instance["meta"]["k"])\" first_host=\"0\"/>\n")
#    end

write(fh,
"""
</clusters>
</grid_info>
<node_infos>
""")

    for i=1:length(rect_list)
        rect = rect_list[i]

       write(fh,
"""
<node_statistics>
<node_property name=\"id\" value=\"$(rect.task_id)\"/>
<node_property name=\"type\" value=\"computation\"/>
<node_property name=\"start_time\" value=\"$(rect.stime)\"/>
<node_property name=\"end_time\" value=\"$(rect.etime)\"/>
<configuration>
  <conf_property name=\"cluster_id\" value=\"$(rect.device_id)\"/>
  <conf_property name=\"host_nb\" value=\"$(rect.nb_p)\"/>
  <host_lists>
    <hosts start=\"$(rect.start_idx-1)\" nb=\"$(rect.nb_p)\"/>
  </host_lists>
</configuration>
</node_statistics>
""")

    end

write(fh,
"""
</node_infos>
</grid_schedule>
""")

    close(fh)
end
