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

import Base.show

type ScheduleRect
    task_id::Int
    device_id::Int
    start_idx::Int
    nb_p::Int
    stime::Float64
    etime::Float64
end

function show(io::IO,object::ScheduleRect)
    println(io,"ScheduleRect")
    println(io,"task_id:   $(object.task_id)")
    println(io,"device_id: $(object.device_id)")
    println(io,"start_idx: $(object.start_idx)")
    println(io,"nb_p : $(object.nb_p)")
    println(io,"stime: $(object.stime)")
    println(io,"etime: $(object.etime)")
end
