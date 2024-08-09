import multiprocessing
import datetime   
import os
import subprocess 
import sys
import math
import time 
from collections import Counter   
import numpy
import signal
import re 

def is_float(value):
    try:
        float(value)
        return float(value)
    except ValueError:
        return 0

def adbshell(command,serial='', popen=True):
  # 进入ADB shell
  #print(serial+':'+command) 
  if serial:
    adb_shell = subprocess.Popen(['adb','-s',serial, 'shell'], stdout=subprocess.PIPE, stdin=subprocess.PIPE) 
  else: 
    adb_shell = subprocess.Popen(['adb', 'shell'], stdout=subprocess.PIPE, stdin=subprocess.PIPE)  
  # 在ADB shell中输入命令 
  command = command+'\n' #命令加回车
  command = command.encode("utf-8") 
  #print(command)  
  adb_shell.stdin.write(command) 
  adb_shell.stdin.write(b'exit\n')   
  adb_shell.stdin.flush()  
  output = adb_shell.stdout.readlines()
  return output




def signal_handler(signum, frame):  
    print('收到信号', signum) 
    for child in multiprocessing.active_children(): 
        child.terminate()  # 强制终止子进程  
    sys.exit()  # 强制终止父进程       

def endworker():  
    print('end ') 
    for child in multiprocessing.active_children(): 
        child.terminate()  # 强制终止子进程  
    sys.exit()  # 强制终止父进程   
    
def percent(a,b):
  #返回2位数的百分比
  n = a/b
  p = f"{n:.2%}" 
  return p

def getAppPid(package,serial=''):
    #获取应用的进程id
    command = "ps -ef|grep '" + package + "'|grep -v grep|grep -v dumpsys|awk '{print $2}'"
    
    resList = adbshell(command,serial)

    pidList = []
    for value in resList:
        if not value:
            continue
        try:
            value=value.decode("utf-8").strip()
            int(value)
            pidList.append(value)
        except:
            log.error(TAG, '获取pid异常，不是整数：' + str(value))

    return pidList
  

def workerfps(process_id,queue,view,serial):
    lostTimestamp = (1 << 63) - 1  #帧未准备好，会返回一个64位的int数，这个数据丢弃
    nanosecondsPerSecond = 1e9 #纳秒转换为秒比例
    baseFilmPeriod = nanosecondsPerSecond/24
    countfps = []
    ftlmsarr = [] #记录帧间隔时间
    result = {}
    countsjanka = 0 #sjank第一个区间，小于5
    countsjankb = 0 #sjank第二个区间，6-10
    countsjankc = 0 #sjank第三个区间，大于10
    countsjank = 0 #计算总数
    countjanka = 0 #jank第一个区间，小于5
    countjankb = 0 #jank第二个区间，6-10
    countjankc = 0 #jank第三个区间，大于10
    countjank = 0 #计算总数
    countbjanka = 0 #bigjank第一个区间，小于5
    countbjankb = 0 #bigjank第二个区间，6-10
    countbjankc = 0 #bigjank第三个区间，大于10
    countbjank = 0 #计算总数
    countgtarr = [] #统计大于帧间隔时间的帧数
    countltarr = [] #统计小于帧间隔时间的帧数
    while True:
        if not queue.empty():
            continue
        command = 'dumpsys SurfaceFlinger --latency \''+view+'\''
        output = adbshell(command,serial)
        
        frameTimeList = []
        frameTimeStampList = []
        ftr = [] #帧间隔数据数组
        i=0
        for line in output:
            #print(line.decode("utf-8").strip())
            strs = line.decode("utf-8").strip()
            
            if i == 0:
                rp = int(strs)
            if strs and i>0:
                sarr = strs.split()
                if int(len(sarr)!=3 or sarr[0])==0 or int(sarr[1])==lostTimestamp:
                    continue
                #frameTimeStampList.append(int(sarr[1]))
                #a = int(((int(sarr[1]) - int(sarr[0]))/nanosecondsPerSecond)*1000)
                #print(str(a)+','+sarr[1]+','+sarr[0])
                #if a >16:
                frameTimeStampList.append(int(sarr[1]))
            i=i+1
       
        fps = int(len(frameTimeStampList)/((frameTimeStampList[-1]-frameTimeStampList[0])/nanosecondsPerSecond))
        #print(str(fps)+','+str(frameTimeStampList[-1])+','+str(frameTimeStampList[0]))
        #sys.exit()
        fpstime = int(1000/fps) 
        frameTimeList = [t2 - t1 for t1, t2 in zip(frameTimeStampList, frameTimeStampList[1:]) if t2-t1>rp]
        
        ftlms = [int((num/nanosecondsPerSecond)*1000) for num in frameTimeList] #帧间隔时间，单位毫秒
        ftlmsarr.extend(ftlms)
        countfps.append(fps) #adb 命令返回的127帧统计
        lencountfps = len(countfps)
        counter = Counter(countfps)
        ftlmsmin = float('%.2f' % numpy.min(ftlmsarr))
        ftlmsmax = float('%.2f' % numpy.max(ftlmsarr))
        ftlmsavg = float('%.2f' % numpy.mean(ftlmsarr))
        ftlms_5 =  sum(1 for x in ftlmsarr if x > 66) 
        ftlms_95 = sum(1 for x in ftlmsarr if x > 100)
        ftlms_200 = sum(1 for x in ftlmsarr if x > 150)
        smallJankList = [t4 for t1, t2, t3, t4 in 
                         zip(frameTimeList, frameTimeList[1:], frameTimeList[2:], frameTimeList[3:])
                         if (t1 + t2 + t3) * 2 < t4 * 3]
        sjank = len(smallJankList)
        countsjank = countsjank+sjank
        if sjank:
            if sjank<=5:
                countsjanka = countsjanka+1
            elif 5<sjank<=10:
                countsjankb +=1
            else:
                countsjankc +=1
        #计算jank
        jankList = [t4 for t1, t2, t3, t4 in 
                            zip(frameTimeList, frameTimeList[1:], frameTimeList[2:], frameTimeList[3:])
                            if (t1 + t2 + t3) * 2 < t4 * 3 and t4 > baseFilmPeriod * 2]
        jank = len(jankList)
        countjank = countjank+jank
        if jank:
            if jank<=5:
                countjanka = countjanka+1
            elif 5<jank<=10:
                countjankb +=1
            else:
                countjankc +=1
        #result['jankTime'] = sum(jankList)
        
        #计算bigjank
        bigJankList = [t4 for t1, t2, t3, t4 in 
                            zip(frameTimeList, frameTimeList[1:], frameTimeList[2:], frameTimeList[3:])
                            if (t1 + t2 + t3) * 2 < t4 * 3 and t4 > baseFilmPeriod * 3]
        bigjank = len(bigJankList)
        countbjank = countbjank+bigjank
        if bigjank:
            if bigjank<=5:
                countbjanka = countjanka+1
            elif 5<bigjank<=10:
                countbjankb +=1
            else:
                countbjankc +=1
                    
        #result['process_id'] = process_id
        result['ftlmsmin'] = ftlmsmin
        result['ftlmsmax'] = ftlmsmax
        result['ftlmsavg'] = ftlmsavg
        result['ftlms_5'] = ftlms_5
        result['ftlms_95'] = ftlms_95
        result['ftlms_200'] = ftlms_200
        result['fps'] = fps
        result['counter'] = counter
        result['lencountfps'] = lencountfps
        result['sjank']=sjank
        result['jank']=jank
        result['bigjank']=bigjank
        result['countsjanka']=countsjanka
        result['countsjankb']=countsjankb
        result['countsjankc']=countsjankc
        result['countjanka']=countjanka
        result['countjankb']=countjankb
        result['countjankc']=countjankc
        result['countbjanka']=countbjanka
        result['countbjankb']=countbjankb
        result['countbjankc']=countbjankc
        result['countsjank']=countsjank
        result['countjank']=countjank
        result['countbjank']=countbjank
        queue.put((result,process_id))
        time.sleep(0.4)      

##获取某个时间点app的接收和发送流量
def collectTrafficData(pidlist,serial=''):
    networkCard = "wlan0"
    recvList = []
    sendList = []
    trafficInfo = []
    bytesToKB = 1024
    for pid in pidlist:
        command = "cat /proc/" + pid + "/net/dev|grep '" + networkCard \
                + "'|awk " + "'{print $2\" \"$10}'"
        #print(command)
        result = adbshell(command,serial)
        for r in result:
            trafficInfo = r.decode("utf-8").strip().split()
            break
        if len(trafficInfo) > 2:
            if trafficInfo[0] == '0' and trafficInfo[1] == '0':
                trafficInfo = trafficInfo[2:]
            if trafficInfo[-1] == '0' and trafficInfo[-2] == '0':
                trafficInfo = trafficInfo[:-2]

        if len(trafficInfo) != 2:
            pidList = []
            return -1, -1, timeStamp
        try:
            int(trafficInfo[0])
            int(trafficInfo[1])
            recvList.append(int(trafficInfo[0]))
            sendList.append(int(trafficInfo[1]))
            recvtmp = int(trafficInfo[0])
        except:
            pidList = []
            return -1, -1, timeStamp

    #recv = float('%.2f' % (sum(recvList) / bytesToKB))
    recv = float('%.2f' % (recvtmp / bytesToKB))
    send = float('%.2f' % (sum(sendList) / bytesToKB))
    timeStamp = getCurrentStamp()
    return recv, send, timeStamp

#获取当前时间，精确到毫秒，返回数据单位为秒
def getCurrentStamp(): 
    timestamp = time.time() * 1000
    return int(timestamp) / 1000 

def workerTraffic(process_id,queue,pidls,serial=''):
    lastRecv = 0 #最近一次收到的流量
    lastSend = 0 #最近一次发送的流量
    lastTime = 0 #最近一次统计的时间点
    recvarr = [] #用于计算带宽数值的情况
    result = {}
    f = 0
    while True:
        #计算带宽情况
        if not queue.empty():
            continue
        recv, send, ctime = collectTrafficData(pidls,serial)
        #print(str(recv)+","+str(send)+","+str(ctime))
        if recv == -1 or send == -1:
            continue
        
        recva = float('%.2f' % (recv - lastRecv))
        senda = float('%.2f' % (send - lastSend))
        testtime = ctime - lastTime
        recvRate = recva / (ctime - lastTime)
        sendRate = senda / (ctime - lastTime)
        
        recvRate = float('%.2f' % recvRate)
        sendRate = float('%.2f' % sendRate)
        
        lastRecv = recv
        lastSend = send
        lastTime = ctime
        if f == 0:
            f = f+1
            continue #第一次取内存的数据过大，丢弃。带宽的计算需要两个数据。
        recvarr.append(recvRate)
        recvmin = float('%.2f' % numpy.min(recvarr))
        recvmax = float('%.2f' % numpy.max(recvarr))
        recvavg = float('%.2f' % numpy.mean(recvarr))
        recv_5 = float('%.2f' % numpy.percentile(recvarr,5))
        recv_95 = float('%.2f' % numpy.percentile(recvarr,95))
        result['recvRate']=recvRate
        result['recvmin']=recvmin
        result['recvmax']=recvmax
        result['recvavg']=recvavg
        result['recv_5']=recv_5
        result['recv_95']=recv_95
        queue.put((result,process_id))
        f = f+1
        time.sleep(0.4)

def workerMem(process_id,queue,package,serial='',m=0):
    #第一次取内存的数据过大，丢弃
    result = {}
    memarr = [] #记录每次采集内存数据
    f = 0
    #m = 0 #标识模拟器
    while True:
        if not queue.empty():
            continue

        if m == 1:
            command = "dumpsys meminfo "+package+"|grep 'TOTAL'|grep PSS"
        else:
            command = "dumpsys meminfo "+package+"|grep 'TOTAL PSS:'"
        
        r = adbshell(command,serial)
        if f == 0:
            f = f+1
            continue #第一次取内存的数据过大，丢弃。带宽的计算需要两个数据
        ###计算内存
        if m == 1:
            mem = r[0].decode("utf-8").strip().split()[1]
        else:
            mem = r[0].decode("utf-8").strip().split()[2]
        memarr.append(mem)
        b = int(memarr[0])
        a = int(memarr[-1])-int(memarr[0])
        memch = str(percent(a,b))
        memcur = str(int(int(mem)/1024))+"Mb"
        memstart = str(int(b/1024))+"Mb"
        result['memcur']=memcur
        result['memstart']=memstart
        result['memch']=memch
        queue.put((result,process_id))
        f = f+1
        time.sleep(0.4)
        
def workerCPU(process_id,queue,greppids,serial):
    ###计算cpu
    result = {}
    cpuarr = [] #记录cpu每次采集的数据
    while True:
        command = 'top -n 1 |egrep "'+greppids+'"|grep com|grep S'
        command = 'top -n 1 |egrep "'+greppids+'"|grep -v egrep'
        r = adbshell(command,serial)
        cpus = []
        for l in r:
            s = l.decode("utf-8").strip().split()[-4]
            cpus.append(is_float(s))
        cpu = sum(cpus) #当前cpu
        if cpu != 0:
            cpuarr.append(cpu)
        if cpu ==0:
            cpu = cpuarr[-1] #如果获取到的cpu为0，用最近的数据
        cpumin = float('%.2f' % numpy.min(cpuarr))
        cpumax = float('%.2f' % numpy.max(cpuarr))
        cpuavg = float('%.2f' % numpy.mean(cpuarr))
        cpu_5 = float('%.2f' % numpy.percentile(cpuarr,5))
        cpu_95 = float('%.2f' % numpy.percentile(cpuarr,95))
        result['cpu']=cpu
        result['cpumin']=cpumin
        result['cpumax']=cpumax
        result['cpuavg']=cpuavg
        result['cpu_5']=cpu_5
        result['cpu_95']=cpu_95
        queue.put((result,process_id))
        time.sleep(0.4)
      
if __name__ == "__main__":
    signal.signal(signal.SIGINT, signal_handler) #按下 Ctrl+C 发送 SIGINT 信号
    serial=''
    if len(sys.argv)>1:
      serial=sys.argv[1] #传入设备号
      
    command = 'dumpsys window|grep mCurrentFocus|grep Window'
    output = adbshell(command,serial)
 
    for line in output:
      #print(line.decode("utf-8").strip())
      strs = line.decode("utf-8").strip().split(' ')
      cwin = strs[2].replace("}","")
      #print(cwin)
    package = cwin.split('/')[0]  #包名
   

    model = ''
    command = 'getprop ro.product.model'
    output = adbshell(command,serial)
    for line in output:
        model = line.decode("utf-8").strip()
      
   
    #command = 'dumpsys SurfaceFlinger|sed -n \'/HWC layers:/,/[*]/p\'|grep qiyi'
    command = "dumpsys SurfaceFlinger|grep 'SurfaceView'|grep BLAST|grep '"+cwin+"'|grep '*'"
    #中国移动云手机app特殊获取view
    if package == 'com.chinamobile.mcloud':
        command = "dumpsys SurfaceFlinger|grep com.chinamobile.mcloud|grep '*'"
    #nova5z手机
    if model == 'SPN-AL00':
        command = "dumpsys SurfaceFlinger|grep '(SurfaceView'|grep '"+cwin+"'|grep '*'"
    
    output = adbshell(command,serial)
    for line in output:
      #print(line.decode("utf-8").strip())
      strs = line.decode("utf-8").strip()
      a = strs.split('#')
      #print(a[1])
      #b = strs.split(']')
      #view = a[0]+'['+cwin+']'+b[2]
      num = a[1].replace(")","")
      view = "SurfaceView["+cwin+"](BLAST)#"+num
     
      if package == 'com.chinamobile.mcloud':
          a = strs.split()
          match = re.search(r'\((.*?)\)', a[3]) 
          view = match.group(1)
      
      #nova5z手机
      if model == 'SPN-AL00':
          a = strs.split()
          view = a[5].replace(")","")   
      break
    
    #print(view) 
    
    pidls = getAppPid(package,serial) #获取应用的进程，可能存在多个
    greppids = '|'.join(pidls)  #用于查询cpu使用率，egrep多个进程号一起查
    
     
    #######创建获取fps数据子进程
    queue = multiprocessing.Queue()  
    p = multiprocessing.Process(target=workerfps, args=("getfps",queue,view,serial,))  
    p.start()
    #######创建获取带宽数据子进程
    trafficQueue = multiprocessing.Queue()  
    trafficProcess = multiprocessing.Process(target=workerTraffic, args=("gettraffic",trafficQueue,pidls,serial,))
    trafficProcess.start()
    #######创建获取内存数据子进程
    memQueue = multiprocessing.Queue()  
    memProcess = multiprocessing.Process(target=workerMem, args=("getmem",memQueue,package,serial,))
    memProcess.start()
    #######创建获取cpu数据子进程
    cpuQueue = multiprocessing.Queue()  
    cpuProcess = multiprocessing.Process(target=workerCPU, args=("getcpu",cpuQueue,greppids,serial,))
    cpuProcess.start()
    starttime =0
    lasttime =0 
    protime = 0
    flag = 0
    while True:
        starttime = getCurrentStamp()
        if lasttime == 0:
            lasttime = starttime
        else:
            protime = starttime - lasttime
            lasttime = starttime
            
        array, process_id = queue.get()  
        #print(f"Process ID: {process_id}, Array: {array}")
        if process_id=="getfps":
            fps = array['fps']
            lencountfps = array['lencountfps']
            ftlmsmin = array['ftlmsmin']
            ftlmsmax = array['ftlmsmax']
            ftlmsavg = array['ftlmsavg']
            ftlms_95 = array['ftlms_95']
            ftlms_5 = array['ftlms_5']
            ftlms_200 = array['ftlms_200']
            counter = array['counter']
            sjank = array['sjank']
            jank = array['jank']
            bigjank = array['bigjank']
            countsjanka = array['countsjanka']
            countsjankb = array['countsjankb']
            countsjankc = array['countsjankc']
            countsjank = array['countsjank']
            countjanka = array['countjanka']
            countjankb = array['countjankb']
            countjankc = array['countjankc']
            countjank = array['countjank']
            countbjanka = array['countbjanka']
            countbjankb = array['countbjankb']
            countbjankc = array['countbjankc']
            countbjank = array['countbjank']
            
        ######带宽情况
        array, process_id = trafficQueue.get()  
        if process_id=="gettraffic":
            recvRate = array['recvRate']
            recvmin = array['recvmin']
            recvmax = array['recvmax']
            recvavg = array['recvavg']
            recv_5 = array['recv_5']
            recv_95 = array['recv_95']
            
            
        #内存情况
        array, process_id = memQueue.get()  
        if process_id=="getmem":
            memstart = array['memstart']
            memcur = array['memcur']
            memch = array['memch']
            
        
        #cpu情况
        array, process_id = cpuQueue.get()  
        if process_id=="getcpu":
            cpu = array['cpu']
            cpumin = array['cpumin']
            cpumax = array['cpumax']
            cpuavg = array['cpuavg']
            cpu_5 = array['cpu_5']
            cpu_95 = array['cpu_95']
            
       
        #屏幕输出区域####################
        os.system('cls')
        #帧率变动情况
        #print(protime) #打印主进程运行时间
        print("当前帧率："+str(fps))   
        print("测试时间（次数）："+str(lencountfps))
        print("帧间隔最小时间"+str(ftlmsmin)+"ms")
        print("帧间隔最大时间"+str(ftlmsmax)+"ms")
        print("帧间隔平均时间"+str(ftlmsavg)+"ms")
        print("帧间隔时间大于66ms帧数："+str(ftlms_5))
        print("帧间隔时间大于100ms帧数："+str(ftlms_95))
        print("帧间隔时间大于150ms帧数："+str(ftlms_200))
        
        fpsstr = ''
        for num,count in counter.items():
        #n = count/lencountfps
        #percent = f"{n:.2%}" 
            p = percent(count,lencountfps)
            fpsstr = fpsstr+"帧率:"+str(num)+",次数:"+str(count)+","+p+'|'
        print(fpsstr)
        #jank变动情况
        print("jank情况###############################")
        print("当前perldog sjank是"+str(sjank))
        print("当前perldog jank是"+str(jank))
        print("当前perldog bigjank是"+str(bigjank))
        print("smallJank情况:"+str(countsjank))
        #print("[1-5] "+str(countsjanka)+"次"+percent(countsjanka,lencountfps)+",[5-10] "+str(countsjankb)+"次"+percent(countsjankb,lencountfps)+",10以上 "+str(countsjankc)+"次"+percent(countsjankc,lencountfps))
        print("Jank情况："+str(countjank))
        #print("[1-5] "+str(countjanka)+"次"+percent(countjanka,lencountfps)+",[5-10] "+str(countjankb)+"次"+percent(countjankb,lencountfps)+",10以上 "+str(countjankc)+"次"+percent(countjankc,lencountfps))
        print("bigJank情况："+str(countbjank))
        #print("[1-5] "+str(countbjanka)+"次"+percent(countbjanka,lencountfps)+",[5-10] "+str(countbjankb)+"次"+percent(countbjankb,lencountfps)+",10以上 "+str(countbjankc)+"次"+percent(countbjankc,lencountfps))
        print("带宽情况###############################")
        print("当前带宽："+str(recvRate)+"kB/s")
        print("最小带宽"+str(recvmin)+"kB/s")
        print("最大带宽"+str(recvmax)+"kB/s")
        print("平均带宽"+str(recvavg)+"kB/s")
        print("95%带宽"+str(recv_5)+"kB/s")
        print("5%带宽"+str(recv_95)+"kB/s")
        print("内存情况###############################")
        print("起始内存："+memstart+",当前内存："+memcur+",变动率："+memch)
        print("cpu情况###############################")
        print("当前cpu使用率："+str(cpu)+"%")
        print("最小cpu使用率"+str(cpumin)+"%")
        print("最大cpu使用率"+str(cpumax)+"%")
        print("平均cpu使用率"+str(cpuavg)+"%")
        print("95%cpu使用率"+str(cpu_5)+"%")
        print("5%cpu使用率"+str(cpu_95)+"%")
        if flag == 9999:
            endworker()
        flag = flag + 1
        time.sleep(0.9)
    #pool.close()  
    #pool.join()
    
    #jank数据改为总和，单位时间看谁出现的总和大