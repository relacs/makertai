import sys
import os
import glob
import argparse
import math as m
import numpy as np

class DataTable:
    def __init__(self):
        self.data = []
        self.header = []
        self.nsecs = 0
        self.units = []
        self.formats = []
        self.setcol = 0
        self.indices = None

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
        for c, f in enumerate(self.formats):
            w = 0
            # extract width from format:
            i0 = -1
            i1 = -1
            for k, s in enumerate(f):
                if i0 < 0 and s.isdigit():
                    i0 = k
                if i0 >= 0 and i1 < 0 and not s.isdigit():
                    i1 = k
                    break
            if i0 >= 0 and i1 >= 0:
                w = int(f[i0:i1])
            else:
                i0 = len(f)-2
                i1 = i0
            if w < len(self.header[c][0]):
                w = len(self.header[c][0])
            if f[-1] == 's':
                for v in self.data[c]:
                    if w < len(v):
                        w = len(v)
            f = f[:i0] + str(w) + f[i1:]
            self.formats[c] = f

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
        if col is not None and not isinstance(col, int):
            col = self.col(col)
        if col is None:
            col = self.setcol
        self.data[col].append(val)
        self.setcol = col+1

    def add_data(self, data, col=None):
        for val in data:
            self.add_value(val, col)
            col = None

    def fill_data(self):
        # maximum rows:
        r = 0
        for c in range(len(self.data)):
            if r < len(self.data[c]):
                r = len(self.data[c])
        # fill up:
        for c in range(len(self.data)):
            while len(self.data[c]) < r:
                self.data[c].append(float('NaN'))

    def sort(self, column):
        if not isinstance(column, int):
            if column.isdigit():
                column = int(column)
            else:
                column = self.col(column)
                if column is None:
                    column = -1
        if column >= 0:
            self.indices = sorted(range(len(self.data[column])), key=self.data[column].__getitem__)

    def write(self, df, table_format='dat', units="row", number_cols=False):
        # table_format: "dat", "ascii", "rtai", "csv", "md", "html", "tex"
        # units: "row", "header" or "none"
        # number_cols: add row with colum numbers
        format_width = True
        begin_str = ''
        end_str = ''
        header_start = '# '
        header_sep = '  '
        header_close = ''
        header_end = '\n'
        data_start = '  '
        data_sep = '  '
        data_close = ''
        data_end = '\n'
        top_line = False
        header_line = False
        bottom_line = False
        if table_format[0] == 'a':
            format_width = True
            begin_str = ''
            end_str = ''
            header_start = '# '
            header_sep = ' | '
            header_close = ''
            header_end = '\n'
            data_start = '  '
            data_sep = ' | '
            data_close = ''
            data_end = '\n'
            top_line = False
            header_line = False
            bottom_line = False
        elif table_format[0] == 'r':
            format_width = True
            begin_str = ''
            end_str = ''
            header_start = 'RTH| '
            header_sep = '| '
            header_close = ''
            header_end = '\n'
            data_start = 'RTD| '
            data_sep = '| '
            data_close = ''
            data_end = '\n'
            top_line = False
            header_line = False
            bottom_line = False
        elif table_format[0] == 'c':
            # cvs according to http://www.ietf.org/rfc/rfc4180.txt :
            number_cols=False
            if units == "row":
                units = "header"
            format_width = False
            header_start=''
            header_sep = ','
            header_close = ''
            header_end='\n'
            data_start=''
            data_sep = ','
            data_close = ''
            data_end='\n'
            top_line = False
            header_line = False
            bottom_line = False
        elif table_format[0] == 'm':
            number_cols=False
            if units == "row":
                units = "header"
            format_width = True
            header_start='| '
            header_sep = ' | '
            header_close = ''
            header_end=' |\n'
            data_start='| '
            data_sep = ' | '
            data_close = ''
            data_end=' |\n'
            top_line = False
            header_line = True
            bottom_line = False
        elif table_format[0] == 'h':
            format_width = False
            begin_str = '<table>\n'
            end_str = '</table>\n'
            header_start='  <tr>\n    <th align="left"'
            header_sep = '</th>\n    <th align="left"'
            header_close = '>'
            header_end='</th>\n  </tr>\n'
            data_start='  <tr>\n    <td'
            data_sep = '</td>\n    <td'
            data_close = '>'
            data_end='</td>\n  </tr>\n'
            top_line = False
            header_line = False
            bottom_line = False
        elif table_format[0] == 't':
            format_width = False
            begin_str = '\\begin{tabular}'
            end_str = '\\end{tabular}\n'
            header_start='  '
            header_sep = ' & '
            header_close = ''
            header_end=' \\\\\n'
            data_start='  '
            data_sep = ' & '
            data_close = ''
            data_end=' \\\\\n'
            top_line = True
            header_line = True
            bottom_line = True

        # begin table:
        df.write(begin_str)
        if table_format[0] == 't':
            df.write('{')
            for f in self.formats:
                if f[1] == '-':
                    df.write('l')
                else:
                    df.write('r')
            df.write('}\n')
        # retrieve column widths:
        widths = []
        for f in self.formats:
            i0 = 1
            if f[1] == '-' :
                i0 =2
            i1=f.find('.')
            widths.append(int(f[i0:i1]))
        # top line:
        if top_line:
            if table_format[0] == 't':
                df.write('  \\hline\n')
            else:
                first = True
                df.write(header_start.replace(' ', '-'))
                for i in range(len(self.header)):
                    if not first:
                        df.write('-'*len(header_sep))
                    first = False
                    df.write(header_close)
                    w = widths[i]
                    df.write(w*'-')
                df.write(header_end.replace(' ', '-'))
        # section and column headers:
        nsec0 = 0
        if table_format[0] in 'cm':
            nsec0 = self.nsecs
        for ns in range(nsec0, self.nsecs+1):
            nsec = self.nsecs-ns
            first = True
            df.write(header_start)
            for i in range(len(self.header)):
                if nsec < len(self.header[i]):
                    if not first:
                        df.write(header_sep)
                    first = False
                    hs = self.header[i][nsec]
                    if nsec == 0 and units == "header":
                        if units and self.units[i] != '1':
                            hs += '/' + self.units[i]
                    # section width and column count:
                    sw = widths[i]
                    columns = 1
                    for k in range(i+1, len(self.header)):
                        if nsec < len(self.header[k]):
                            break
                        sw += len(header_sep) + widths[k]
                        columns += 1
                    if table_format[0] == 'h':
                        if columns>1:
                            df.write(' colspan="%d"' % columns)
                    elif table_format[0] == 't':
                        df.write('\\multicolumn{%d}{l}{' % columns)
                    df.write(header_close)
                    if format_width:
                        f = '%%-%ds' % sw
                        df.write(f % hs)
                    else:
                        df.write(hs)
                    if table_format[0] == 't':
                        df.write('}')
            df.write(header_end)
        # units:
        if units == "row":
            first = True
            df.write(header_start)
            for i in range(len(self.header)):
                if not first:
                    df.write(header_sep)
                first = False
                df.write(header_close)
                if table_format[0] == 't':
                    df.write('\\multicolumn{1}{l}{%s}' % self.units[i])
                else:
                    if format_width:
                        f = '%%-%ds' % widths[i]
                        df.write(f % self.units[i])
                    else:
                        df.write(self.units[i])
            df.write(header_end)
        # column numbers:
        if number_cols:
            first = True
            df.write(header_start)
            for i in range(len(self.header)):
                if not first:
                    df.write(header_sep)
                first = False
                df.write(header_close)
                if table_format[0] == 't':
                    df.write('\\multicolumn{1}{l}{%d}' % (i+1))
                else:
                    if format_width:
                        f = '%%%dd' % widths[i]
                        df.write(f % (i+1))
                    else:
                        df.write("%d" % (i+1))
            df.write(header_end)
        # header line:
        if header_line:
            if table_format[0] == 'm':
                df.write('|')
                for i in range(len(self.header)):
                    w = widths[i]+2
                    if self.formats[i][1] == '-':
                        df.write(w*'-' + '|')
                    else:
                        df.write((w-1)*'-' + ':|')
                df.write('\n')
            elif table_format[0] == 't':
                df.write('  \\hline\n')
            else:
                first = True
                df.write(header_start.replace(' ', '-'))
                for i in range(len(self.header)):
                    if not first:
                        df.write(header_sep.replace(' ', '-'))
                    first = False
                    df.write(header_close)
                    w = widths[i]
                    df.write(w*'-')
                df.write(header_end.replace(' ', '-'))
        # data:
        if self.indices is None or len(self.indices) != len(self.data[0]):
            self.indices = range(len(self.data[0]))
        for k in self.indices:
            first = True
            df.write(data_start)
            for c, f in enumerate(self.formats):
                if not first:
                    df.write(data_sep)
                first = False
                if table_format[0] == 'h':
                    if f[1] != '-':
                        df.write(' align="right"')
                df.write(data_close)
                if isinstance(self.data[c][k], float) and m.isnan(self.data[c][k]):
                    if format_width:
                        fn = '%%%ds' % widths[c]
                        df.write(fn % '-')
                    else:
                        df.write('-')
                else:
                    ds = f % self.data[c][k]
                    if not format_width:
                        ds = ds.strip()
                    df.write(ds)
            df.write(data_end)
        # bottom line:
        if bottom_line:
            if table_format[0] == 't':
                df.write('  \\hline\n')
            else:
                first = True
                df.write(header_start.replace(' ', '-'))
                for i in range(len(self.header)):
                    if not first:
                        df.write('-'*len(header_sep))
                    first = False
                    df.write(header_close)
                    w = widths[i]
                    df.write(w*'-')
                df.write(header_end.replace(' ', '-'))
        # end table:
        df.write(end_str)

                    
def parse_filename(filename, dt):
    # dissect filename:
    cols = filename.split('-')
    kernel = '-'.join(cols[2:5])
    host = cols[1]
    num = cols[5]
    date = '-'.join(cols[6:9])
    quality = cols[-1]
    load = cols[-2]
    param = cols[9:-2]
    cpuid='0'
    latency='-'
    performance='no'
    remove = []
    for p in param:
        if p[0:3] == 'cpu':
            cpuid = p[3:]
            remove.append('cpu'+cpuid)
        if p == 'nolatency':
            latency='user'
            remove.append(p)
        if p == 'nocpulatency':
            latency='cpu'
            remove.append(p)
        if p == 'nocpulatencyall':
            latency='kern'
            remove.append(p)
        if p == 'performance':
            performance='yes'
            remove.append(p)
    for r in remove:
        param.remove(r)
    param = '-'.join(param)

    dt.add_value(num, dt.col('data>num'))
    dt.add_value(param, dt.col('data>kernel parameter'))
    dt.add_value(load, dt.col('data>load'))
    dt.add_value(quality, dt.col('data>quality'))
    dt.add_value(latency, dt.col('data>latency'))
    dt.add_value(performance, dt.col('data>performance'))

    return cpuid

def analyze_latencies(data, outlier):
    if len(data) == 0:
        return  float('NaN'),  float('NaN'), float('NaN')
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
    if len(data) == 0:
        return  [float('NaN')]
    mean = np.mean(data)
    minv = np.min(data)
    maxv = np.max(data)
    return [maxv]


def main():
    init = 10
    outlier = 0.0  # percent
    sort_col = '-1'
    number_cols = False
    table_format = 'dat'

    # command line arguments:
    parser = argparse.ArgumentParser(
        description='Analyse RTAI test results.',
        epilog='by Jan Benda (2018)')
    parser.add_argument('--version', action='version', version="1.0")
    parser.add_argument('-i', nargs=1, default=[init],
                        type=int, metavar='LINES', dest='init',
                        help='number of initial lines to be skipped (defaults to {0:d})'.format(init))
    parser.add_argument('-p', nargs=1, default=[outlier],
                        type=float, metavar='PERCENT', dest='outlier',
                        help='percentile defining outliers (defaults to {0:g}%%)'.format(outlier))
    parser.add_argument('-s', nargs=1, default=[sort_col],
                        type=str, metavar='COLUMN', dest='sort_col',
                        help='sort results according to COLUMN')
    parser.add_argument('-f', nargs=1, default=[table_format],
                        type=str, metavar='FORMAT', dest='table_format',
                        help='output format of summary table (defaults to {0:s}%%)'.format(table_format))
    parser.add_argument('-n', dest='number_cols', action='store_true',
                        help='add line with column numbers to header')
    parser.add_argument('file', nargs='*', default='', type=str,
                        help='latency-* file with RTAI test results')
    args = parser.parse_args()

    init = args.init[0]
    outlier = args.outlier[0]
    number_cols = args.number_cols
    table_format = args.table_format[0]
    sort_col = args.sort_col[0]

    dt = DataTable()
    dt.add_section('data')
    dt.add_column('num', '1', '%3s')
    dt.add_column('kernel parameter', '1', '%-20s')
    dt.add_column('load', '1', '%-5s')
    dt.add_column('quality', '1', '%-7s')
    dt.add_column('cpuid', '1', '%-5s')
    dt.add_column('latency', '1', '%-4s')
    dt.add_column('performance', '1', '%-3s')
    dt.add_column('temp', 'C', '%5.1f')
    dt.add_column('freq', 'GHz', '%6.3f')
    dt.add_column('poll', '%', '%5.1f')

    # list files:
    files = []
    if len(args.file) == 0:
        files = sorted(glob.glob('latencies-*'))
    else:
        for filename in args.file:
            if filename == 'avg':
                sort_col = 'avg'
            elif filename == 'max':
                sort_col = 'max'
            elif os.path.isfile(filename):
                files.append(filename)
            elif os.path.isdir(filename):
                files.extend(sorted(glob.glob(os.path.join(filename, 'latencies-*'))))
            else:
                print('file "' + filename + '" does not exist.')
    # analyze files:
    for filename in files:
        with open(filename) as sf:
            
            cpuid = parse_filename(filename, dt)

            # gather test data:
            intest = False
            data = {}
            for line in sf:
                if 'Loaded modules' in line:
                    break
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

            # gather other data:
            coretemp = float('NaN')
            cpufreq = float('NaN')
            poll = float('NaN')
            inenvironment = False
            incputopology = False
            incputemperatures = False
            for line in sf:
                if 'Environment' in line:
                    inenvironment = True
                if inenvironment:
                    if "tests run on cpu" in line:
                        cpuid = line.split(':')[1].strip()
                    if line.strip() == '':
                        inenvironment = False
                if 'CPU topology' in line:
                    incputopology = True
                if incputopology:
                    if 'cpu'+cpuid in line:
                        cols = line.split()
                        if len(cols) >= 5:
                            cpufreq = float(cols[4].strip())
                        if len(cols) >= 9:
                            poll = float(cols[8].strip().rstrip('%'))
                    if line.strip() == '':
                        incputopology = False
                if 'CPU core temperatures' in line:
                    incputemperatures = True
                if incputemperatures:
                    if 'Core '+cpuid in line:
                        coretemp = float(line.split(':')[1].split()[0].lstrip('+').rstrip('\xc2\xb0C'))
                    if line.strip() == '':
                        incputemperatures = False

            # fill table:                    
            dt.add_value('cpu'+cpuid, dt.col('data>cpuid'))
            dt.add_value(coretemp, dt.col('data>temp'))
            dt.add_value(cpufreq, dt.col('data>freq'))
            dt.add_value(poll, dt.col('data>poll'))

            # analyze:
            for testmode in ['kern', 'kthreads', 'user']:
                if (testmode, 'latency', 'latencies') in data:
                    # provide columns:
                    if not dt.exist(testmode+' latency'):
                        dt.add_section('kern latency')
                        dt.add_column('mean jitter', 'ns', '%7.0f')
                        dt.add_column('stdev', 'ns', '%7.0f')
                        dt.add_column('max', 'ns', '%7.0f')
                        dt.add_column('overruns', '1', '%6.0f')
                    # analyze latency test:
                    latencies = data[testmode, 'latency', 'latencies']
                    overruns = data[testmode, 'latency', 'overruns']
                    overruns = np.diff(overruns)
                    dt.add_data(analyze_latencies(latencies[init:], outlier), dt.col(testmode+' latency>mean jitter'))
                    dt.add_data(analyze_overruns(overruns[init:]), dt.col(testmode+' latency>overruns'))
                elif (testmode, 'preempt', 'latencies') in data:
                    # analyze preempt test:
                    #print np.mean(data[testmode, 'latency', 'latencies'])
                    pass
            dt.fill_data()

    # write results:
    dt.adjust_columns()
    if sort_col == 'avg':
        sort_col = 'kern latency>mean jitter'
    elif sort_col == 'max':
        sort_col = 'kern latency>max'
    dt.sort(sort_col)
    dt.write(sys.stdout, number_cols=number_cols, table_format=table_format)


if __name__ == '__main__':
    main()

# latency:
#RTH|    lat min|    ovl min|    lat avg|    lat max|    ovl max|   overruns

# prempt:          
# RTH|     lat min|     lat avg|     lat max|    jit fast|    jit slow
