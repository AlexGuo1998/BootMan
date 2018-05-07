import sys

def gendoc(filename):
    f = open(filename)
    data = f.read()
    f.close()
    lines = data.split('\n')
    dimstart = -1
    outdata = ""
    label = "file:"
    for i in range(len(lines)):
        if lines[i] != "" and lines[i][0] == ';':
            #dim
            if dimstart < 0:
                #record start
                dimstart = i
        else:
            if lines[i] != "" and lines[i][-1] == ':':
                #label
                label = lines[i]
            if dimstart >= 0:
                #write
                if i - dimstart > 1:

                    outdata += str(dimstart + 1) + ":\n"
                    outdata += label + '\n'
                    for j in range(dimstart, i):
                        outdata += lines[j] + '\n'
                    outdata += "\n\n\n"
                #reset
                
                dimstart = -1
    return outdata

out = gendoc(sys.argv[1])

f = open(sys.argv[2], mode = "w")
f.write(out)
f.close()
