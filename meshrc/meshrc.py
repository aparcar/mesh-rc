import subprocess
import datetime
from flask import Flask, request, session, g, redirect, url_for, abort, \
        render_template, flash, jsonify

from .prometheus_2_netjson import PromNetJson


app = Flask(__name__)
app.config.from_object(__name__)

p2nj = PromNetJson()

@app.route("/")
@app.route("/graph")
def graph():
    bmx = request.args.get("bmx", "7")
    return render_template("graph.html", bmx=bmx)

@app.route("/netjson")
def grap_json():
    bmx = request.args.get("bmx", "7")
    time = request.args.get('time', "")
    timestamp=""
    if time != "":
        if time[0] == "-":
            value = int(time[1:-1])
            suffix = time[-1]
            seconds = 0
            minutes = 0
            hours = 0
            days = 0
            weeks = 0
            if suffix == "s":
                seconds = value
            elif suffix == "m":
                minutes = value
            elif suffix == "h":
                hours = value
            elif suffix == "d":
                days = value
            elif suffix == "w":
                weeks = value
            delta = datetime.datetime.now() - datetime.timedelta(
                    seconds=seconds, minutes=minutes, hours=hours, days=days,
                    weeks=weeks)
            timestamp = delta.timestamp()
    return jsonify(p2nj.get_bmx7(timestamp))

@app.route("/overview")
def overview():
    return render_template("overview.html",
            nodes=p2nj.get_nodes_bmx7())

@app.route("/config")
def config():
    return render_template("config.html")

@app.route("/config/<node_id>")
def config_node(node_id):
    return render_template("config_node.html",
            hostname=p2nj.get_hostname(node_id))

@app.route("/config/<node_id>/<hostname>")
def config_node_hostname(node_id, hostname):
    if node_id and hostname:
        cmdline = "lime-bmx7-server-cli -h {} {}".format(node_id, hostname)
        proc = subprocess.Popen(
                cmdline.split(),
                shell=False
                )
        output, errors = proc.communicate()
        flash("Node {} renamed to {}".format(node_id, hostname))
        #file_name = "/var/run/bmx7/sms/sendSms/name_{}".format(node_id)
        #with open(file_name, "w") as node_config:
        #    node_config.write("hostname")
        #os.system("/usr/sbin/bmx7 -c syncSms {}".format(file_name))
        redirect("/overview")
    else:
        return 500, ""

@app.template_filter('duration')
def duration_filter(d):
    if d == "down":
        return d
    days, rest = divmod(int(d), (60*60*24))
    hours, rest = divmod(rest, (60*60))
    minutes, rest = divmod(rest, 60)
    if days > 1: return "{}d".format(days)
    elif days == 1: return "{}h".format(hours + 24)
    elif hours > 1: return "{}h".format(hours)
    elif hours == 1: return "{}h".format(minutes + 60)
    else: return "{}m".format(minutes)