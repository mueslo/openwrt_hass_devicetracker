#!/usr/bin/env python3
#logging
import logging
from logging.handlers import RotatingFileHandler

# scheduling & persistence
import sqlite3
import atexit
from datetime import datetime, timedelta
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.jobstores.sqlalchemy import SQLAlchemyJobStore
from apscheduler.jobstores.base import JobLookupError

# web requests
import requests
import json
from flask import Flask, jsonify, g, redirect, request, url_for


app = Flask(__name__)
db_root = "lastseen"
db_name = lambda x: 'sqlite:///' + x + ".sqlite.db"

apikey = your_api_key
apiurl = "https://api.pushbullet.com/v2/pushes"
apiheader = {"Content-Type": "application/json"}

jobstores = {'default': SQLAlchemyJobStore(url=db_name(db_root + '.jobs'))}

#if not app.debug or os.environ.get('WERKZEUG_RUN_MAIN') == 'true':
#    # to not run twice in flask's master/child debug environment
scheduler = BackgroundScheduler(jobstores=jobstores)
scheduler.start()
atexit.register(lambda: scheduler.shutdown())
    
from sqlalchemy import Column, Integer, Boolean, String, TIMESTAMP, func, ForeignKey, not_, select
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
Base = declarative_base()
    
class Person(Base):
    __tablename__ = 'person'
    id = Column(Integer, primary_key=True)
    name = Column(String)
    
    devices = relationship('Device', back_populates='owner', uselist=True)
    
    @hybrid_property
    def gone(self):
        return all(d.gone for d in self.devices)
    
    @gone.expression
    def gone(cls):
        return select(
                [not_(func.min(Device.gone))]
            ).where(
                Device.owner_id==cls.id
            #).group_by(
            #    cls.id
            ).label('gone')

persons = {1: 'Anton', 2: 'Bruce', 3: 'Charles'}
dev_own = {'30:19:57:e8:d5:5a': 1,
           '30:19:57:e8:d5:5b': 2,
           '30:19:57:e8:d5:5c': 3}

class Device(Base):
    __tablename__ = 'device'
    mac = Column(String(17), primary_key=True)
    host = Column(String, default=None)
    owner_id = Column(Integer, ForeignKey(Person.id), nullable=True)

    connected = Column(Boolean, default=False)
    gone = Column(Boolean, default=True)
    t = Column(TIMESTAMP, onupdate=func.current_timestamp())
    
    owner = relationship(Person, back_populates="devices")
    set_gone_job = relationship('SetGoneJob', back_populates="device", uselist=False)
    
class SetGoneJob(Base):
    __tablename__ = 'set_gone_job'
    mac = Column(String(17), ForeignKey(Device.mac), primary_key=True)
    id = Column(String)
    
    device = relationship(Device, back_populates="set_gone_job")

from sqlalchemy import create_engine
from sqlalchemy.orm import scoped_session, sessionmaker

engine = create_engine(db_name(db_root), convert_unicode=True, connect_args={'check_same_thread':False})
db_session = scoped_session(sessionmaker(autocommit=False,
                                         bind=engine))

Base.metadata.create_all(engine)
for id, name in persons.items():
    if not db_session.query(Person).get(id):
        db_session.add(Person(id=id, name=name))
db_session.commit()


gone_threshold = timedelta(minutes=3)


def notify_worker(*message, push=False):
    data = json.dumps({"type":"note","title":"Wifi Watch","body": ' '.join(message)})
    app.logger.info('notify: %s', ' '.join(message))
    if push:
        app.logger.info(requests.post(apiurl, auth=(apikey,""), headers=apiheader, data=data))


def notify(*args, **kwargs):
    scheduler.add_job(func=notify_worker, args=args, kwargs=kwargs)


def set_gone(mac):
    device = db_session.query(Device).get(mac)
    device.gone = True
    
    job = device.set_gone_job
    db_session.delete(job)
    db_session.commit()
    
    notify(device.host, "is gone")
    if device.owner and device.owner.gone:
        notify(device.owner.name, "is gone", push=True)


def reset_gone_job(device):
    job = db_session.query(SetGoneJob).get(device.mac)

    try:
        scheduler.remove_job(job.id)
        app.logger.info('deleted job %s', job.id)
    except AttributeError: #job is None
        return False
    except JobLookupError:
        app.logger.warning('state mismatch: job %s already deleted', job.id)
        db_session.delete(job)
        return False
    else:
        db_session.delete(job)
        app.logger.info('reset gone setter for %s', device.host)
        return True


@app.before_request
def before_request():
    g.now = datetime.now()

@app.teardown_appcontext
def shutdown_session(exception=None):
    db_session.remove()

def update_connection_state(device, new_connected):
    update_type = '{}connected'.format("" if new_connected else "dis")
    app.logger.info('%s %s', update_type, device.host)
    if device.connected == new_connected:
        app.logger.warning('state mismatch: %s already %s', device.host, update_type)
    device.connected = new_connected


def process_state(device, new_connected):
    if new_connected:
        update_connection_state(device, True)
        reset_gone_job(device)
        if device.gone:
            notify(device.host, "is back")
            device.gone = False
            if device.owner and not device.owner.gone:
                notify(device.owner.name, "is back", push=True)
    else:
        update_connection_state(device, False)
        if reset_gone_job(device):
            app.logger.warning('state mismatch: job for %s already existed...?', device.host)
        
        job_id = scheduler.add_job(
            func=set_gone,
            args=(device.mac,),
            trigger='date',
            run_date=g.now+gone_threshold).id
        db_session.add(SetGoneJob(mac=device.mac, id=job_id))
        app.logger.info('scheduled gone setter for %s', device.host)


@app.route('/event', methods=['POST'])
def event():
    try:
        payload = request.get_json()
        app.logger.debug("got %s", payload)
        mac = payload['mac']
        device = db_session.query(Device).get(mac)
        if device is None:
            device = Device(mac=mac, host=payload['host'])
            db_session.add(device)
        else:
            device.host = payload['host'] #update hostname
        msg = payload['msg']
        
        if msg == 'AP-STA-CONNECTED':
            process_state(device, True)
        elif msg == 'AP-STA-POLL-OK':
            if device.connected:
                device.t = func.current_timestamp()
            else:
                process_state(device, True)
        elif msg == 'AP-STA-DISCONNECTED':
            process_state(device, False)
        elif msg in ('CTRL-EVENT-TERMINATING', 'AP-DISABLED'):
            app.logger.error('radio shutting down! %s', msg)
            app.logger.error('we should really hook into openwrt ifup with hotplug...')
        else:
            app.logger.warning('unknown event %s %s %s', device.host, mac, msg)
            
        db_session.commit()
    except:
        raise
    else:
        return 'success'


@app.route('/state', methods=['POST'])
def state():
    try:
        # check/load data
        payload = request.get_json()
        app.logger.debug("got %s", payload)
        
        changes = False
        disconnected = {d.mac:d for d in db_session.query(Device).all()}
        for row in payload:
            mac = row['mac']
            device = db_session.query(Device).get(mac)
            if device is None:
                device = Device(mac=mac, host=row['host'])
                db_session.add(device)
            else:
                device.host = row['host'] #update hostname
            disconnected.pop(mac, None)
            if not device.connected: #connected.get(mac, False):
                process_state(device, True)
                changes = True
                
        for device in disconnected.values(): # those that aren't sent are implicitly disconnected
            if device.connected:
                process_state(device, False)
                changes = True
                
        if changes:
            db_session.commit()
            app.logger.warning("state mismatch: local state was not up to date!")
    except:
        raise
        #return 'failure\n'
    else:
        return 'success\n'
           
           
@app.route('/')
def index():
    res_p = db_session.query(Person.name, not_(func.min(Device.gone))).join(Device).group_by(Person.id).all()
    
    res_d = db_session.query(Device).outerjoin(Person).filter(Device.gone == False).all()
    return jsonify({'persons': {r.name: r[1] for r in res_p},
                    'devices':
                        {r.mac: {
                            'host': r.host,
                            'owner': r.owner.name if r.owner else r.owner,
                            'connected': r.connected,
                            'gone': r.gone} for r in res_d}})


@app.errorhandler(500)
def internal_error(exception):
    app.logger.error(exception)
    return render_template('500.html'), 500


if __name__ == '__main__':
    handler = RotatingFileHandler(db_root+'.log', maxBytes=2**17, backupCount=1)
    handler.setLevel(logging.INFO)
    handler.setFormatter(logging.Formatter(
    '[%(asctime)s] %(levelname)s: %(message)s'))
    app.logger.addHandler(handler)
    app.run(debug=True, host='0.0.0.0', port=8088) # http://localhost:5001/
else:
    application = app # for a WSGI server e.g.,
    # twistd -n web --wsgi=hello_world.application --port tcp:5001:interface=localhost
