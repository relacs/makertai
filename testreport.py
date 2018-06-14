import sys
import argparse
import numpy as np

class DataTable:
    def __init__(self):
        self.data = []
        self.header = []
        self.nsecs = 0
        self.units = []
        self.formats = []
        self.sep = ' | '
        self.setcol = 0

    def add_section(self, label):
        if self.setcol >= len(self.data):
            self.header.append([label])
            self.units.append('')
            self.formats.append('')
            self.data.append([])
        else:
            self.header[self.setcol] = [label] + self.header[self.setcol]
        if self.nsecs < len(self.header[self.setcol]):
            self.nsecs = len(self.header[self.setcol])
        self.setcol = len(self.data)-1
        
    def add_column(self, label, unit, formats):
        if self.setcol >= len(self.data):
            self.header.append([label])
            self.formats.append(formats)
            self.units.append(unit)
            self.data.append([])
        else:
            self.header[self.setcol] = [label] + self.header[self.setcol]
            self.units[self.setcol] = unit
            self.formats[self.setcol] = formats
        self.setcol = len(self.data)
        return len(self.header)

    def set_format(self, col, format):
        self.formats[col] = format
        self.setcol = col

    def adjust_columns(self):
        for k, f in enumerate(self.formats):
            if f[-1] == 's':
                w = 0
                for v in self.data[k]:
                    if w < len(v):
                        w = len(v)
                if f[1] == '-':
                    self.formats[k] = '%%-%ds' % w
                else:
                    self.formats[k] = '%%%ds' % w

    def col(self, label):
        ss = label.rstrip('>').split('>')
        maxns = self.nsecs
        si = 0
        while ss[si] == '':
            maxns -= 1
        if maxns < 0:
            maxns = 0
        for ns in range(maxns+1):
            nsec = maxns-ns
            if ss[si] == '':
                si += 1
                continue
            for i in range(len(self.header)):
                if nsec < len(self.header[i]) and self.header[i][nsec] == ss[si]:
                    si += 1
                    if si >= len(ss):
                        return i
                    elif nsec > 0:
                        break
        return None

    def exist(self, label):
        return self.col(label) is not None

    def add_value(self, val, col=None):
        if col is None:
            col = self.setcol
        # elif col is string:
        # col = self.col(col) # check None return value
        self.data[col].append(val)
        self.setcol = col+1

    def add_data(self, data, col=None):
        for val in data:
            self.add_value(val, col)
            col = None

    def write(self, df):
        # retrieve column widths:
        widths = []
        for f in self.formats:
            i0 = 1
            if f[1] == '-' :
                i0 =2
            i1=f.find('.')
            widths.append(int(f[i0:i1]))
        # section and column headers:
        for ns in range(self.nsecs+1):
            nsec = self.nsecs-ns
            first = True
            df.write('# ')
            for i in range(len(self.header)):
                if nsec < len(self.header[i]):
                    if not first:
                        df.write(self.sep)
                    first = False
                    # section width:
                    sw = widths[i]
                    for k in range(i+1, len(self.header)):
                        if nsec < len(self.header[k]):
                            break
                        sw += len(self.sep) + widths[k]
                    f = '%%-%ds' % sw
                    df.write(f % self.header[i][nsec])
            df.write('\n')
        # units:
        first = True
        df.write('# ')
        for i in range(len(self.header)):
            if not first:
                df.write(self.sep)
            first = False
            f = '%%-%ds' % widths[i]
            df.write(f % self.units[i])
        df.write('\n')
        # column number:
        first = True
        df.write('# ')
        for i in range(len(self.header)):
            if not first:
                df.write(self.sep)
            first = False
            f = '%%%dd' % widths[i]
            df.write(f % (i+1))
        df.write('\n')
        # data:
        for k in range(len(self.data[0])):
            first = True
            df.write('  ')
            for c, f in enumerate(self.formats):
                if not first:
                    df.write(self.sep)
                first = False
                df.write(f % self.data[c][k])
            df.write('\n')
            

init = 10
outlier = 0.0  # percent

# command line arguments:
parser = argparse.ArgumentParser(
    description='Analyse RTAI test results.',
    epilog='by Jan Benda (2018)')
parser.add_argument('--version', action='version', version="1.0")
parser.add_argument('-i', nargs=1, default=[init],
                    type=int, metavar='N', dest='init',
                    help='number of initial lines to be skipped (defaults to {0:d})'.format(init))
parser.add_argument('-p', nargs=1, default=[outlier],
                    type=float, metavar='P', dest='outlier',
                    help='percentile defining outliers (defaults to {0:g}%%)'.format(outlier))
parser.add_argument('file', nargs='*', default='', type=str,
                    help='latency-* file with RTAI test results')
args = parser.parse_args()

init = args.init[0]
outlier = args.outlier[0]

def analyze_latencies(data):
    coredata = data
    if outlier > 0.0 :
        l, m, h = np.percentile(data, [outlier, 50.0, 100.0-outlier])
        coredata = data[(data>=l)&(data<=h)]
    mean = np.mean(coredata)
    std = np.std(coredata)
    minv = np.min(data)
    maxv = np.max(data)
    return mean, std, maxv

def analyze_overruns(data):
    mean = np.mean(data)
    minv = np.min(data)
    maxv = np.max(data)
    return mean, maxv

dt = DataTable()
dt.add_section('data')
dt.add_section('')
dt.add_column('num', '1', '%3s')
dt.add_column('param', '1', '%-20s')

for filename in args.file:
    with open(filename) as sf:
        # gather data:
        intest = False
        data = {}
        for line in sf:
            if 'test:' in line:
                intest = True
                tests = line.split()[0]
                testmode, testtype = tests.split('/')
                latencies = []
                overruns = []
                jitterfast = []
                jitterslow = []
            if '------------' in line:
                intest = False
                if testtype == 'latency':
                    data[testmode, testtype, 'latencies'] = np.array(latencies)
                    data[testmode, testtype, 'overruns'] = np.array(overruns)
                elif testtype == 'preempt':
                    data[testmode, testtype, 'latencies'] = np.array(latencies)
                    data[testmode, testtype, 'jitterfast'] = np.array(jitterfast)
                    data[testmode, testtype, 'jitterslow'] = np.array(jitterslow)
            if intest:
                cols = line.split('|')
                if cols[0] == 'RTD':
                    if testtype == 'latency':
                        latencies.append(int(cols[4])-int(cols[1]))
                        overruns.append(int(cols[6]))
                    elif testtype == 'preempt':
                        latencies.append(int(cols[3])-int(cols[1]))
                        jitterfast.append(int(cols[4]))
                        jitterslow.append(int(cols[5]))
    
        # dissect filename:
        cols = filename.split('-')
        kernel = '-'.join(cols[1:4])
        host = cols[4]
        num = cols[5]
        date = '-'.join(cols[6:9])
        param = '-'.join(cols[9:])
        dt.add_value(num, dt.col('data>num'))
        dt.add_value(param, dt.col('data>param'))

        # analyze:
        for testmode in ['kern', 'kthreads', 'user']:
            if (testmode, 'latency', 'latencies') in data:
                # provide columns:
                if not dt.exist(testmode+' latency'):
                    dt.add_section('kern latency')
                    dt.add_section('jitter')
                    dt.add_column('mean', 'ns', '%7.0f')
                    dt.add_column('stdev', 'ns', '%7.0f')
                    dt.add_column('max', 'ns', '%7.0f')
                    dt.add_section('overruns')
                    dt.add_column('mean', '1', '%6.0f')
                    dt.add_column('max', '1', '%6.0f')
                # analyze latency test:
                latencies = data[testmode, 'latency', 'latencies']
                overruns = data[testmode, 'latency', 'overruns']
                overruns = np.diff(overruns)
                dt.add_data(analyze_latencies(latencies[init:]), dt.col(testmode+' latency>jitter'))
                dt.add_data(analyze_overruns(overruns[init:]), dt.col(testmode+' latency>overruns'))
            elif (testmode, 'preempt', 'latencies') in data:
                # analyze preempt test:
                #print np.mean(data[testmode, 'latency', 'latencies'])
                pass

# write results:
dt.adjust_columns()
dt.write(sys.stdout)

# latency:
#RTH|    lat min|    ovl min|    lat avg|    lat max|    ovl max|   overruns

# prempt:          
# RTH|     lat min|     lat avg|     lat max|    jit fast|    jit slow
