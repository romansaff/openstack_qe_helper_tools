#!/usr/bin/env python
# Created by Roman Safronov

import csv
import sys

from datetime import datetime

from bokeh.plotting import figure, output_file, save
from bokeh.models import ColumnDataSource, HoverTool, CustomJS
from bokeh.models.formatters import DatetimeTickFormatter

output_file("tempest_threads_graph.html", title="tempest threads graph")

sources = {}
sources_failed = {}

try:
    input_file = sys.argv[1]
except IndexError:
    print ("No input file specified")
    exit()

def update_data(source, row):
    source[key].data['time'].append(
        datetime.strptime(row[0], '%Y-%m-%d %H:%M:%S'))
    source[key].data['thread'].append(row[1])
    source[key].data['event'].append(row[2])

with open(input_file, 'r') as file:
    csvreader = csv.reader(file)
    first_row=True
    for row in csvreader:
        if first_row:
            first_row = False
            continue
        if not(row[1] in list(sources.keys())):
            key = row[1]
            sources[key] = ColumnDataSource(
                data=dict(time=[], thread=[], event=[]))
            sources_failed[key] = ColumnDataSource(
                data=dict(time=[], thread=[], event=[]))
        update_data(sources, row)
        if row[3] == 'Yes':
            update_data(sources_failed, row)

p = figure(title="Tempest threads and tests start time",
           x_axis_label="time",
           y_axis_label="tempest thread id",
           y_range=list(reversed(sources.keys())),
           x_axis_type='datetime',
           x_axis_location="above",
           width=1600,
           tools='pan, box_zoom, reset')

p.xaxis.formatter = DatetimeTickFormatter(
    hours = '%Y-%m-%d %H:%M',
    days = '%Y-%m-%d %H:%M',
    hourmin = '%Y-%m-%d %H:%M',
    minsec = '%H:%M:%S',
    minutes = '%H:%M:%S',
    seconds = '%H:%M:%S')
hover = HoverTool(
    tooltips=[
        ('Time', '@time{%F %T}'),
        ('Event', '@event'),],
    formatters={'@time': 'datetime'},
    renderers=[])

for thread in list(sources.keys()):
    line = p.line(
        'time', 'thread', legend_label=thread, line_width=5,
        source=sources[thread])
    circle = p.circle(
        'time', 'thread', fill_color="white", size=8,
        source=sources[thread])
    circle_red = p.circle(
        'time', 'thread', fill_color="red", size=8,
        source=sources_failed[thread])
    hover.renderers.append(circle)

p.tools.append(hover)

save(p)
