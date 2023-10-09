#!/usr/bin/env python
# Created by Roman Safronov

import os
import re
import subprocess
import sys

threads = {}
try:
    input_file = sys.argv[1]
except IndexError:
    print ("No input file specified")
    exit()

failed_events = []
subunit_files = [f for f in os.listdir('.') if re.match(r'.*\.subunit', f)]
for subunit_file in subunit_files:
    cmd = "subunit-trace -n --failonly --no-summary < {}".format(subunit_file)
    try:
        output = subprocess.getoutput(cmd)
    except subprocess.CalledProcessError as e:
        output = str(e.output)
    special_events = ['setUp', 'setUpClass', 'tearDownClass', '_run_cleanups']
    finished = output.split('\n')
    for line in finished:
        if 'FAILED' in line:
            line = line.split()
            if any(event in line for event in special_events):
                failed_events.append('{}:{}'.format(line[2][1:-1].split('.')[-1], line[1]))
            else:
                failed_events.append(('{}:{}'.format(*line[1].split('.')[-2:])))

print('"Timestamp","Thread","Test","Failed"')
with open(input_file) as infile:
    for line in infile:
        if re.search('INFO', line) or re.search('DEBUG', line):
            line_data = line.split()
            thread_id = line_data[2]
            timestamp = line_data[0] + " " + line_data[1][:-4]
            if not(thread_id in threads.keys()):
                threads[thread_id] = {}
            if re.search('Request\s\(', line):
                event = line[line.find("(")+1:line.find(")")]
                if event in ['main', 'None']:
                    continue
                if not(event in threads[thread_id].keys()):
                    threads[thread_id][event] = timestamp
            else:
                threads[thread_id]['End'] = timestamp

for thread_id in sorted(threads.keys()):
    if len(threads[thread_id]) == 1:
        continue
    sorted_dict = dict(sorted(threads[thread_id].items(), key=lambda x:x[1]))
    for event in sorted_dict.keys():
        failed = 'Yes' if event in failed_events else 'No'
        print ('"{}","{}","{}","{}"'.format(
            sorted_dict[event], thread_id, event, failed))
