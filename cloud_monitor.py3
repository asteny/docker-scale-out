#!/usb/bin/env python3
#
# Cloud monitoring server to get commands from Slurm to start and stop cloud nodes
#
import socket
import sys
import os
import subprocess
import signal
import stat
import json
from shlex import quote
import daemon
from daemon import pidfile
import logging
import logging.handlers
import traceback
import signal
import time

dcompose = sys.argv[1]
compose_yaml = sys.argv[2]
pid_file = sys.argv[3]
server_address = sys.argv[4]

def run(logger): 
    active_nodes = 0
    requested_nodes = set()
    node_names = dict() # docker tag -> requested hostname

    # Make sure the socket does not already exist
    try:
        os.unlink(server_address)
    except OSError:
        if os.path.exists(server_address):
            raise

    # Create a UDS socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(server_address)
    #allow anyone to write to the socket
    os.chmod(server_address, stat.S_IROTH | stat.S_IWOTH)

    # Listen for incoming connections
    sock.listen(1)

    logger.info("Listening on %s" % (server_address))

    while True:
        connection=None
        try:
            logger.info('waiting for a connection')
            connection, client_address = sock.accept()
            logger.info('new connection')

            connection.settimeout(10)
            data = connection.recv(4096).decode('utf-8').strip()
            connection.shutdown(socket.SHUT_RD)
            logger.info('received "%s"' % (data))
            if data:
                op = data.split(":", 1)
                if op[0] == "stop":
                    tag=node_names[op[1]]

                    os.system("docker rm -f \"%s\"" % (quote(tag)))
                    node_names.pop(tag, None)
                    connection.sendall(b'ACK')
                    active_nodes -= 1
                elif op[0] == "start":
                    #increase node count by 1
                    requested_nodes.add(op[1])
                    active_nodes += 1

                    rc = subprocess.run(["/bin/bash", "-c", "%s -f %s up --scale cloud=%s --no-recreate -d 2>&1" %
                                         (dcompose, compose_yaml, active_nodes)],
                                        capture_output=True, cwd=os.getcwd())

                    logger.info("stdout: %s" % (rc.stdout));
                    logger.info("rc: %s" % (rc.returncode));

                    connection.sendall(b'ACK')
                elif op[0] == "whoami":
                    found=False

                    # already known hash
                    for requested_node, short_node in node_names.items():
                        if short_node == op[1]:
                            found=True
                            break

                    if not found:
                        short_node=op[1]
                        requested_node = requested_nodes.pop()
                        node_names[requested_node]=short_node

                    if requested_node:
                        logger.info("responding: %s=%s" % (requested_node, short_node))
                        connection.sendall(requested_node.encode('utf-8'))
                    else:
                        connection.sendall(b'FAIL')

                    logger.info("Active Nodes=%s Known Nodes[%s]=%s" % (active_nodes, len(node_names), node_names))
                else:
                    connection.sendall(b'FAIL')

            connection.close()
        except socket.timeout:
            logger.error('connection timeout')
        except BrokenPipeError:
            logger.error('ignoring broken pipe')
        except KeyboardInterrupt:
            logger.error('shutting down')
            break;

    sock.close()
    os.unlink(server_address)

if __name__ == "__main__":
    logger = logging.getLogger('scaleout')
    logger.setLevel(logging.INFO)
    fh = logging.handlers.SysLogHandler(address = '/dev/log')
    fh.ident = "scaleout: "
    logger.addHandler(fh)

    if os.path.exists(pid_file):
        pid=0
        with open(pid_file, 'rb') as f:
                pid=int(f.read())

        try:
            os.kill(pid, signal.SIGINT)
        except ProcessLookupError:
            logger.debug("found stale pidfile")

        time.sleep(0.1)

        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            logger.debug("signal sigkill failed...which is good")

        try:
            os.unlink(pid_file)
        except FileNotFoundError:
            logger.debug("unlink stale pidfile failed...which is good")

    with daemon.DaemonContext(pidfile=pidfile.TimeoutPIDLockFile(pid_file, 1)):
        logger = logging.getLogger('scaleout')
        logger.setLevel(logging.INFO)
        fh = logging.handlers.SysLogHandler(address = '/dev/log')
        fh.ident = "scaleout: "
        logger.addHandler(fh)

        try:
            run(logger)

        except Exception as e:
            logger.error("failed: %s" % (e))
            logger.error(traceback.format_exc())
