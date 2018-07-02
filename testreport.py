import sys
import os
import glob
import argparse
import math as m
import numpy as np
import matplotlib.pyplot as plt

class DataTable:
    formats = ['dat', 'ascii', 'rtai', 'csv', 'md', 'html', 'tex']
    column_numbering = ['num', 'index', 'aa', 'AA']

    def __init__(self):
        self.data = []
        self.shape = (0, 0)
        self.header = []
        self.nsecs = 0
        self.units = []
        self.formats = []
        self.hidden = []
        self.setcol = 0
        self.addcol = 0
        self.indices = None

    def add_section(self, label):
        if self.addcol >= len(self.data):
            self.header.append([label])
            self.units.append('')
            self.formats.append('')
            self.hidden.append(False)
            self.data.append([])
        else:
            self.header[self.addcol] = [label] + self.header[self.addcol]
        if self.nsecs < len(self.header[self.addcol]):
            self.nsecs = len(self.header[self.addcol])
        self.addcol = len(self.data)-1
        self.shape = (self.columns(), self.rows())
        return self.addcol
        
    def add_column(self, label, unit, formats):
        if self.addcol >= len(self.data):
            self.header.append([label])
            self.formats.append(formats)
            self.units.append(unit)
            self.hidden.append(False)
            self.data.append([])
        else:
            self.header[self.addcol] = [label] + self.header[self.addcol]
            self.units[self.addcol] = unit
            self.formats[self.addcol] = formats
        self.addcol = len(self.data)
        self.shape = (self.columns(), self.rows())
        return self.addcol-1

    def section(self, column, level):
        column = self.col(column)
        return self.header[column][level]
    
    def set_section(self, label, column, level):
        column = self.col(column)
        self.header[column][level] = label
        return column

    def label(self, column):
        column = self.col(column)
        return self.header[column][0]

    def set_label(self, label, column):
        column = self.col(column)
        self.header[column][0] = label
        return column

    def unit(self, column):
        column = self.col(column)
        return self.unit[column]

    def set_unit(self, unit, column):
        column = self.col(column)
        self.units[column] = unit
        return column

    def format(self, column):
        column = self.col(column)
        return self.format[column]

    def set_format(self, format, column):
        column = self.col(column)
        self.formats[column] = format
        return column

    def columns(self):
        return len(self.header)

    def rows(self):
        return max(map(len, self.data))
        
    def __len__(self):
        return self.columns()

    def __iter__(self):
        self.iter_counter = -1
        return self

    def __next__(self):
        self.iter_counter += 1
        if self.iter_counter >= self.columns():
            raise StopIteration
        else:
            return self.data[self.iter_counter]

    def next(self):  # python 2
        return self.__next__()

    def __getitem__(self, key):
        if type(key) is tuple:
            index = key[0]
        else:
            index = key
        if isinstance(index, slice):
            start = self.col(index.start)
            stop = self.col(index.stop)
            newindex = slice(start, stop, index.step)
        elif type(index) is list or type(index) is tuple or type(index) is np.ndarray:
            newindex = [self.col(inx) for inx in index]
            if type(key) is tuple:
                return [self.data[i][key[1]] for i in newindex]
            else:
                return [self.data[i] for i in newindex]
        else:
            newindex = self.col(index)
        if type(key) is tuple:
            return self.data[newindex][key[1]]
        else:
            return self.data[newindex]
        return None

    def key_value(self, col, row, missing='-'):
        col = self.col(col)
        if col is None:
            return ''
        if isinstance(self.data[col][row], float) and m.isnan(self.data[col][row]):
            v = missing
        else:
            u = self.units[col] if self.units[col] != '1' else ''
            v = (self.formats[col] % self.data[col][row]) + u
        return self.header[col][0] + '=' + v

    def _find_col(self, ss, si, minns, maxns, c0, strict=True):
        if si >= len(ss):
            return None, None, None, None
        ns0 = 0
        for ns in range(minns, maxns+1):
            nsec = maxns-ns
            if ss[si] == '':
                si += 1
                continue
            for c in range(c0, len(self.header)):
                if nsec < len(self.header[c]) and \
                    ( ( strict and self.header[c][nsec] == ss[si] ) or
                      ( not strict and ss[si] in self.header[c][nsec] ) ):
                    ns0 = ns
                    c0 = c
                    si += 1
                    if si >= len(ss):
                        c1 = len(self.header)
                        for c in range(c0+1, len(self.header)):
                            if nsec < len(self.header[c]):
                                c1 = c
                                break
                        return c0, c1, ns0, None
                    elif nsec > 0:
                        break
        return None, c0, ns0, si

    def find_col(self, column):
        # column: int or str or None
        if column is None:
            return None, None
        if not isinstance(column, int) and column.isdigit():
            column = int(column)
        if isinstance(column, int):
            if column >= 0 and column < len(self.formats):
                return column, column+1
            else:
                return None, None
        # find column by header:
        ss = column.rstrip('>').split('>')
        maxns = self.nsecs
        si0 = 0
        while si0 < len(ss) and ss[si0] == '':
            maxns -= 1
            si0 += 1
        if maxns < 0:
            maxns = 0
        c0, c1, ns, si = self._find_col(ss, si0, 0, maxns, 0, True)
        if c0 is None and c1 is not None:
            c0, c1, ns, si = self._find_col(ss, si, ns, maxns, c1, False)
        return c0, c1
    
    def col(self, column):
        c0, c1 = self.find_col(column)
        return c0

    def exist(self, column):
        # column: int or str or None
        return self.col(column) is not None

    def add_value(self, val, column=None):
        column = self.col(column)
        if column is None:
            column = self.setcol
        self.data[column].append(val)
        self.setcol = column+1
        self.shape = (self.columns(), self.rows())

    def add_data(self, data, column=None):
        for val in data:
            self.add_value(val, column)
            column = None

    def set_column(self, column):
        col = self.col(column)
        if col is None:
            print('column ' + column + ' not found')
        self.setcol = col
        return col

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
        self.setcol = 0
        self.shape = (self.columns(), self.rows())

    def hide(self, column):
        c0, c1 = self.find_col(column)
        if c0 is not None:
            for c in range(c0, c1):
                self.hidden[c] = True

    def hide_all(self):
        for c in range(len(self.hidden)):
            self.hidden[c] = True

    def hide_empty_columns(self, missing='-'):
        for c in range(len(self.data)):
            # check for empty column:
            isempty = True
            for v in self.data[c]:
                if isinstance(v, float):
                    if not m.isnan(v):
                        isempty = False
                        break
                else:
                    if v != missing:
                        isempty = False
                        break
            if isempty:
                self.hidden[c] = True

    def show(self, column):
        c0, c1 = self.find_col(column)
        if c0 is not None:
            for c in range(c0, c1):
                self.hidden[c] = False

    def adjust_columns(self, missing='-'):
        for c, f in enumerate(self.formats):
            w = 0
            # extract width from format:
            i0 = 1
            if f[1] == '-' :
                i0 = 2
            i1 = f.find('.')
            if len(f[i0:i1]) > 0:
                w = int(f[i0:i1])
            # adapt width to header:
            if w < len(self.header[c][0]):
                w = len(self.header[c][0])
            # adapt width to data:
            if f[-1] == 's':
                for v in self.data[c]:
                    if w < len(v):
                        w = len(v)
            else:
                for v in self.data[c]:
                    if isinstance(v, float) and m.isnan(v):
                        s = missing
                    else:
                        s = f % v
                    if w < len(s):
                        w = len(s)
            # set width of format string:
            f = f[:i0] + str(w) + f[i1:]
            self.formats[c] = f
                
    def sort(self, columns):
        if type(columns) is not list and type(columns) is not tuple:
            columns = [ columns ]
        if len(columns) == 0:
            return
        self.indices = range(len(self.data[0]))
        for col in reversed(columns):
            rev = False
            if len(col) > 0 and col[0] in '^!':
                rev = True
                col = col[1:]
            c = self.col(col)
            if c is None:
                print('sort column ' + col + ' not found')
                continue
            self.indices = sorted(self.indices, key=self.data[c].__getitem__, reverse=rev)

    def write_keys(self, sep='>', space=None):
        fh = self.nsecs * ['']
        for hl in self.header:
            fh[0:len(hl)] = hl
            for n in range(len(hl)):
                n0 = len(hl)-n-1
                line = sep.join(reversed(fh[n0:]))
                if space is not None:
                    line = line.replace(' ', space)
                print(line)

    def index2aa(self, n, a='a'):
        # inspired by https://stackoverflow.com/a/37604105
        d, m = divmod(n, 26)
        bm = chr(ord(a)+m)
        return index2aa(d-1, a) + bm if d else bm

    def write(self, df, table_format='dat', units="row", number_cols=None, missing='-'):
        # table_format: "dat", "ascii", "rtai", "csv", "md", "html", "tex"
        # units: "row", "header" or "none"
        # number_cols: add row with colum numbers ('num', 'index') or letters ('aa' or 'AA')
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
            header_start = '| '
            header_sep = ' | '
            header_close = ''
            header_end = ' |\n'
            data_start = '| '
            data_sep = ' | '
            data_close = ''
            data_end = ' |\n'
            top_line = True
            header_line = True
            bottom_line = True
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
            number_cols=None
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
            number_cols=None
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
            begin_str = '<table>\n<thead>\n'
            end_str = '</tbody>\n</table>\n'
            header_start='  <tr class="header">\n    <th align="left"'
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
                i0 = 2
            i1 = f.find('.')
            if len(f[i0:i1]) > 0:
                widths.append(int(f[i0:i1]))
            else:
                widths.append(1)
        # top line:
        if top_line:
            if table_format[0] == 't':
                df.write('  \\hline\n')
            else:
                first = True
                df.write(header_start.replace(' ', '-'))
                for c in range(len(self.header)):
                    if self.hidden[c]:
                        continue
                    if not first:
                        df.write('-'*len(header_sep))
                    first = False
                    df.write(header_close)
                    w = widths[c]
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
            for c in range(len(self.header)):
                if nsec < len(self.header[c]):
                    # section width and column count:
                    sw = -len(header_sep)
                    columns = 0
                    if not self.hidden[c]:
                        sw = widths[c]
                        columns = 1
                    for k in range(c+1, len(self.header)):
                        if nsec < len(self.header[k]):
                            break
                        if self.hidden[k]:
                            continue
                        sw += len(header_sep) + widths[k]
                        columns += 1
                    if columns == 0:
                        continue
                    if not first:
                        df.write(header_sep)
                    first = False
                    if table_format[0] == 'h':
                        if columns>1:
                            df.write(' colspan="%d"' % columns)
                    elif table_format[0] == 't':
                        df.write('\\multicolumn{%d}{l}{' % columns)
                    df.write(header_close)
                    hs = self.header[c][nsec]
                    if nsec == 0 and units == "header":
                        if units and self.units[c] != '1':
                            hs += '/' + self.units[c]
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
            for c in range(len(self.header)):
                if self.hidden[c]:
                    continue
                if not first:
                    df.write(header_sep)
                first = False
                df.write(header_close)
                if table_format[0] == 't':
                    df.write('\\multicolumn{1}{l}{%s}' % self.units[c])
                else:
                    if format_width:
                        f = '%%-%ds' % widths[c]
                        df.write(f % self.units[c])
                    else:
                        df.write(self.units[c])
            df.write(header_end)
        # column numbers:
        if number_cols is not None:
            first = True
            df.write(header_start)
            for c in range(len(self.header)):
                if self.hidden[c]:
                    continue
                if not first:
                    df.write(header_sep)
                first = False
                df.write(header_close)
                i = c
                if number_cols == 'num':
                    i = c+1
                aa = self.index2aa(c, 'a')
                if number_cols == 'AA':
                    aa = self.index2aa(c, 'A')
                if table_format[0] == 't':
                    if number_cols == 'num' or number_cols == 'index':
                        df.write('\\multicolumn{1}{l}{%d}' % i)
                    else:
                        df.write('\\multicolumn{1}{l}{%s}' % aa)
                else:
                    if number_cols == 'num' or number_cols == 'index':
                        if format_width:
                            f = '%%%dd' % widths[c]
                            df.write(f % i)
                        else:
                            df.write("%d" % i)
                    else:
                        if format_width:
                            f = '%%%ds' % widths[c]
                            df.write(f % aa)
                        else:
                            df.write(aa)
            df.write(header_end)
        # header line:
        if header_line:
            if table_format[0] == 'm':
                df.write('|')
                for c in range(len(self.header)):
                    if self.hidden[c]:
                        continue
                    w = widths[c]+2
                    if self.formats[c][1] == '-':
                        df.write(w*'-' + '|')
                    else:
                        df.write((w-1)*'-' + ':|')
                df.write('\n')
            elif table_format[0] == 't':
                df.write('  \\hline\n')
            else:
                first = True
                df.write(header_start.replace(' ', '-'))
                for c in range(len(self.header)):
                    if self.hidden[c]:
                        continue
                    if not first:
                        df.write(header_sep.replace(' ', '-'))
                    first = False
                    df.write(header_close)
                    w = widths[c]
                    df.write(w*'-')
                df.write(header_end.replace(' ', '-'))
        # start table data:
        if table_format[0] == 'h':
            df.write('</thead>\n<tbody>\n')
        # data:
        if self.indices is None or len(self.indices) != len(self.data[0]):
            self.indices = range(len(self.data[0]))
        for i, k in enumerate(self.indices):
            first = True
            if table_format[0] == 'h':
                eo = "even" if i % 2 == 1 else "odd"
                df.write('  <tr class"%s">\n    <td' % eo)
            else:
                df.write(data_start)
            for c, f in enumerate(self.formats):
                if self.hidden[c]:
                    continue
                if not first:
                    df.write(data_sep)
                first = False
                if table_format[0] == 'h':
                    if f[1] == '-':
                        df.write(' align="left"')
                    else:
                        df.write(' align="right"')
                df.write(data_close)
                if isinstance(self.data[c][k], float) and m.isnan(self.data[c][k]):
                    if format_width:
                        if f[1] == '-':
                            fn = '%%-%ds' % widths[c]
                        else:
                            fn = '%%%ds' % widths[c]
                        df.write(fn % missing)
                    else:
                        df.write(missing)
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
                for c in range(len(self.header)):
                    if self.hidden[c]:
                        continue
                    if not first:
                        df.write('-'*len(header_sep))
                    first = False
                    df.write(header_close)
                    w = widths[c]
                    df.write(w*'-')
                df.write(header_end.replace(' ', '-'))
        # end table:
        df.write(end_str)

                    
def parse_filename(filename, dt):
    # dissect filename:
    cols = os.path.basename(filename).split('-')
    kernel = '-'.join(cols[2:5])
    host = cols[1]
    num = cols[5]
    date = '-'.join(cols[6:9])
    quality = cols[-1]
    load = cols[-2]
    if load == 'cimn':
        load = 'full'
    else:
        load.replace('c', 'cpu ')
        load.replace('i', 'io ')
        load.replace('m', 'mem ')
        load.replace('n', 'net ')
        load = load.strip()
    param = cols[9:-2]
    cpuid=0
    latency='-'
    governor='-'
    remove = []
    for p in param:
        if p[0:3] == 'cpu':
            cpuid = int(p[3:])
            remove.append('cpu%d' % cpuid)
        if 'isol' in p:
            remove.append(p)
        if p == 'plain':
            remove.append(p)
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
            governor='perf'
            remove.append(p)
    for r in remove:
        param.remove(r)
    param = '-'.join(param)

    dt.add_value(num, 'data>num')
    dt.add_value(param, 'data>kernel parameter')
    dt.add_value(load, 'data>load')
    dt.add_value(latency, 'data>latency')
    dt.add_value(governor, 'data>governor')
    dt.add_value(quality, 'data>quality')

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
    return [maxv, len(data)]


def main():
    init = 10
    outlier = 0.0  # percent
    number_cols = None
    table_format = 'dat'

    # command line arguments:
    parser = argparse.ArgumentParser(
        description='Analyse RTAI test results.',
        epilog='by Jan Benda (2018)')
    parser.add_argument('--version', action='version', version="1.0")
    parser.add_argument('-i', default=init, type=int, metavar='LINES', dest='init',
                        help='number of initial lines to be skipped (defaults to %(default)s)')
    parser.add_argument('-p', default=outlier, type=float, metavar='PERCENT', dest='outlier',
                        help='percentile defining outliers (defaults to %(default)s%%)')
    parser.add_argument('-s', action='append', default=[],
                        type=str, metavar='COLUMN', dest='sort_columns',
                        help='sort results according to %(metavar)s (index or header). Several columns can be specified by repeated -s options. If the first character of %(metavar)s is a ^, then the column is sorted in reversed order.')
    parser.add_argument('--hide', action='append', default=[],
                        type=str, metavar='COLUMN', dest='hide_cols',
                        help='hide column %(metavar)s (index or header)')
    parser.add_argument('--select', action='append', default=[],
                        type=str, metavar='COLUMN', dest='select_cols',
                        help='select column %(metavar)s (index or header) only')
    parser.add_argument('--add', action='append', default=[],
                        type=str, metavar='KEY=VALUE', dest='add_cols',
                        help='add a column with header KEY and data value VALUE')
    parser.add_argument('-f', nargs='?', default=table_format, const='dat', dest='table_format',
                        choices=DataTable.formats,
                        help='output format of summary table (defaults to "%(default)s")')
    parser.add_argument('-u', default=True, action='store_false', dest='units',
                        help='do not print units')
    parser.add_argument('-n', default=None, const='num', nargs='?', dest='number_cols',
                        choices=DataTable.column_numbering,
                        help='add line with column numbers/indices/letters to header')
    parser.add_argument('-m', default='-', dest='missing',
                        help='string used to indicate missing values')
    parser.add_argument('-g', nargs='?', default='no', const='show',
                        dest='plots', metavar='FILE',
                        help='show or save histogram plots to %(metavar)s')
    parser.add_argument('file', nargs='*', default='', type=str,
                        help='latency-* file with RTAI test results')
    args = parser.parse_args()

    init = args.init
    outlier = args.outlier
    units = 'row' if args.units else 'none'
    number_cols = args.number_cols
    table_format = args.table_format
    sort_columns = [s.replace('_', ' ').replace(':', '>') for s in args.sort_columns]
    hide_cols = args.hide_cols
    select_cols = args.select_cols
    add_cols = args.add_cols
    missing = args.missing
    plots = False if args.plots == 'no' else True
    plotfile = args.plots if plots and args.plots != 'show' else None

    dt = DataTable()
    dt.add_section('data')
    add_data = []
    for a in add_cols:
        ak, av = a.split('=')
        dt.add_column(ak, '1', '%-s')
        add_data.append(av)
    dt.add_column('num', '1', '%3s')
    dt.add_column('kernel parameter', '1', '%-5s')
    dt.add_column('isolcpus', '1', '%-d')
    dt.add_column('cpu', '1', '%-d')
    dt.add_column('load', '1', '%-s')
    dt.add_column('latency', '1', '%-s')
    dt.add_column('governor', '1', '%-s')
    dt.add_column('temp', 'C', '%4.1f')
    dt.add_column('freq', 'GHz', '%5.3f')
    dt.add_column('poll', '%', '%4.1f')
    dt.add_column('quality', '1', '%-s')
    for testmode in ['kern', 'kthreads', 'user']:
        dt.add_section(testmode+' latencies')
        dt.add_column('mean jitter', 'ns', '%3.0f')
        dt.add_column('stdev', 'ns', '%3.0f')
        dt.add_column('max', 'ns', '%3.0f')
        dt.add_column('overruns', '1', '%1.0f')
        dt.add_column('n', 's', '%d')
        dt.add_section(testmode+' switches')
        dt.add_column('susp', 'ns', '%3.0f')
        dt.add_column('sem', 'ns', '%3.0f')
        dt.add_column('rpc', 'ns', '%3.0f')
        dt.add_section(testmode+' preempt')
        dt.add_column('max', 'ns', '%3.0f')
        dt.add_column('jitfast', 'ns', '%3.0f')
        dt.add_column('jitslow', 'ns', '%3.0f')
        dt.add_column('n', '1', '%d')

    # list files:
    files = []
    sort_name = False
    if len(args.file) == 0:
        files = sorted(glob.glob('latencies-*'))
    else:
        for filename in args.file:
            if filename == 'avg':
                sort_columns = ['kern latencies>mean jitter'] + sort_columns
                sort_name = True
            elif filename == 'max':
                sort_columns = ['kern latencies>max'] + sort_columns
                sort_name = True
            elif os.path.isfile(filename):
                files.append(filename)
            elif os.path.isdir(filename):
                files.extend(sorted(glob.glob(os.path.join(filename, 'latencies-*'))))
            else:
                print('file "' + filename + '" does not exist.')
    if sort_name and len(args.file) == 1 and len(files) == 0:
        files = sorted(glob.glob('latencies-*'))

    # common part of file name:
    common_name = os.path.commonprefix(['-'.join(os.path.basename(f).split('-')[9:]) for f in files])

    if plots:
        fig = plt.figure(figsize=(5,3.5), dpi=80)
        ax = fig.add_subplot(1, 1, 1)
        logbins = np.logspace(2.0, 5.0, 100)
        #ax.set_title(common_name + ': kern latencies')
        ax.set_title('kern latencies')
        ax.set_xscale('log')
        ax.set_xlabel('Jitter [ns]')
        ax.set_yscale('log', nonposy='clip')
        ax.set_ylim(0.5, 1000)
        ax.set_ylabel('Count')
                        
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
                    switches = []
                if '------------' in line:
                    intest = False
                    if testtype == 'latency':
                        data[testmode, testtype, 'latencies'] = np.array(latencies)
                        data[testmode, testtype, 'overruns'] = np.array(overruns)
                    elif testtype == 'switches':
                        data[testmode, testtype, 'switches'] = np.array(switches)
                    elif testtype == 'preempt':
                        data[testmode, testtype, 'latencies'] = np.array(latencies)
                        data[testmode, testtype, 'jitterfast'] = np.array(jitterfast)
                        data[testmode, testtype, 'jitterslow'] = np.array(jitterslow)
                if intest:
                    if testtype == 'switches':
                        if 'SWITCH TIME' in line:
                            cols = line.split()
                            switches.append(int(cols[-2]))
                    else:        
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
            isolcpus = float('NaN')
            coretemp = float('NaN')
            cpufreq = float('NaN')
            poll = float('NaN')
            inparameter = False
            inenvironment = False
            incputopology = False
            incputemperatures = False
            for line in sf:
                if 'Kernel parameter' in line:
                    inparameter = True
                if inparameter:
                    if 'isolcpus' in line:
                        isolcpus = int(list(filter(str.isdigit, line))[0])
                    if line.strip() == '':
                        inparameter = False
                if 'Environment' in line:
                    inenvironment = True
                if inenvironment:
                    if "tests run on cpu" in line:
                        cpuid = int(line.split(':')[1].strip())
                    if line.strip() == '':
                        inenvironment = False
                if 'CPU topology' in line:
                    incputopology = True
                if incputopology:
                    if 'cpu%d' % cpuid in line:
                        cols = line.split()
                        if len(cols) >= 5:
                            cpufreq = float(cols[4].strip())
                            if cpufreq > 1000.0:
                                cpufreq *= 0.001
                        if len(cols) >= 9:
                            poll = float(cols[8].strip().rstrip('%'))
                    if line.strip() == '':
                        incputopology = False
                if 'CPU core temperatures' in line:
                    incputemperatures = True
                if incputemperatures:
                    if 'Core %d' % cpuid in line:
                        coretemp = float(line.split(':')[1].split()[0].lstrip('+').rstrip('\xc2\xb0C'))
                    if line.strip() == '':
                        incputemperatures = False

            # fill table:
            dt.add_data(add_data, 'data>')
            dt.add_value(isolcpus, 'data>isolcpus')
            dt.add_value(cpuid, 'data>cpu')
            dt.add_value(coretemp, 'data>temp')
            dt.add_value(cpufreq, 'data>freq')
            dt.add_value(poll, 'data>poll')

            # analyze:
            for testmode in ['kern', 'kthreads', 'user']:
                if (testmode, 'latency', 'latencies') in data:
                    # analyze latency test:
                    latencies = data[testmode, 'latency', 'latencies']
                    overruns = data[testmode, 'latency', 'overruns']
                    overruns = np.diff(overruns)
                    dt.add_data(analyze_latencies(latencies[init:], outlier),
                                testmode+' latencies>mean jitter')
                    dt.add_data(analyze_overruns(overruns[init:]),
                                testmode+' latencies>overruns')
                    if plots:
                        if len(sort_columns) > 0:
                            l = ', '.join([dt.key_value(s, -1, missing) for s in sort_columns])
                        else:
                            l = '-'.join(os.path.basename(filename).split('-')[9:-1])
                            l = l.replace(common_name, '')
                        ax.hist(latencies, logbins, alpha=0.5, label=l)
                if (testmode, 'switches', 'switches') in data:
                    # analyze switches test:
                    dt.add_data(data[testmode, 'switches', 'switches'],
                                testmode+' switches>susp')
                if (testmode, 'preempt', 'latencies') in data:
                    # analyze preempt test:
                    dt.add_value(data[testmode, 'preempt', 'latencies'][-1],
                                 testmode+' preempt>max')
                    dt.add_value(data[testmode, 'preempt', 'jitterfast'][-1],
                                 testmode+' preempt>jitfast')
                    dt.add_value(data[testmode, 'preempt', 'jitterslow'][-1],
                                 testmode+' preempt>jitslow')
                    dt.add_value(len(data[testmode, 'preempt', 'jitterslow']),
                                 testmode+' preempt>n')
            dt.fill_data()

    # write table keys for makertaikernel.cfg file:
    #dt.write_keys(':', '_')
    #return
                
    # write results:
    dt.hide_empty_columns()
    dt.adjust_columns()
    dt.sort(sort_columns)
    for hs in hide_cols:
        dt.hide(hs.replace('_', ' ').replace(':', '>'))
    if len(select_cols) > 0:
        dt.hide_all()
        for ss in select_cols:
            dt.show(ss.replace('_', ' ').replace(':', '>'))
    dt.write(sys.stdout, number_cols=number_cols, table_format=table_format,
             units=units, missing=missing)

    # close plots:
    if plots:
        ax.legend()
        fig.tight_layout()
        if plotfile is None:
            plt.show()
        else:
            plt.savefig(plotfile)
            plt.close()


if __name__ == '__main__':
    main()
