# Factorio MapShot Containerised

*You can find the MapShot repository created by [Palats](https://github.com/Palats) [here](https://github.com/Palats/mapshot)*

This repository contains resources that generates a docker container of [Palats'](https://github.com/Palats) [mapshot](https://github.com/Palats/mapshot)

The entrypoint itself is rather simple:

1. If Factorio is not already installed, the script will download and extract it, requiring `FACTORIO_USERNAME` and `FACTORIO_TOKEN` for authentication.
2. Depending on the value of `MAPSHOT_MODE`, it will either:
  1. **Render**: Render the map using the provided configurations (such as `MAPSHOT_AREA`, `MAPSHOT_JPEG_QUALITY`, etc.), then quit and restart based on a configured `MAPSHOT_INTERVAL`. or
  2. **Serve**: Serve the map using the built-in mapshot server.

Several default paths and settings are configurable via environment variables, allowing the script to be flexible and customizable for different setups, however running two containers side-by-side, one to serve, one to render, seems to be the most flexible implementation.

## Environment Variables

The following environment variables are used in the provided shell script, and here is a description of each one, explaining what it does:

| Environment Variable                  | Default Value                                       | Description                                       |
| ------------------------------------- | --------------------------------------------------- | --------------------------------------------------- |
| MAPSHOT_PREFIX                        | "mapshot"                                           | Mapshot will prefix all files it creates with that value. |
| MAPSHOT_ROOT_DIRECTORY                | "/opt/mapshot"                                      | Defines the root directory where Mapshot and Factorio data are stored. |
| MAPSHOT_FACTORIO_DATA_DIRECTORY       | "${MAPSHOT_ROOT_DIRECTORY}/factorio"                | Specifies the directory where Factorio data (saves, mods, etc.) is stored. |
| MAPSHOT_FACTORIO_BINARY_PATH          | "${MAPSHOT_ROOT_DIRECTORY}/factorio/bin/x64/factorio" | Defines the path to the Factorio binary (executable). |
| MAPSHOT_WORKING_DIRECTORY             | "${MAPSHOT_ROOT_DIRECTORY}"                         | Defines the working directory for temporary files during Factorio operations. |
| MAPSHOT_KEEP_ONLY_LATEST              | "false"                                             | When set to "true," ensures that only the latest map rendering is kept, deleting older renders. |
| MAPSHOT_INTERVAL                      | 600                                                 | Defines the interval (in seconds) between map renders when the script is running in render mode. A higher value means fewer renders. |
| MAPSHOT_SAVE_MODE                     | N/A                                                 | When set to "latest", the `MAPSHOT_SAVE_NAME` variable is ignored, and the most recently modified save file in `FACTORIO_SAVE_PATH` is automatically discovered and used based on its modification time. |
| MAPSHOT_SAVE_NAME                     | N/A                                                 | Specifies the name of the save file to use for rendering. If not set, the default save file is used. |
| FACTORIO_RELEASE                      | "stable"                                            | Determines which release of Factorio to use. Options include "stable" and "experimental". |
| FACTORIO_AUTO_UPDATE                  | "true"                                              | If set to "true," automatically updates Factorio to the latest release within the specified release tier. |
| FACTORIO_SAVE                         | "/opt/factorio/saves/dummy.zip"                     | Specifies the full path to the Factorio save file that will be used for map rendering. This is the save file the mapshot tool will render into an image. |
| FACTORIO_SAVE_PATH                    | The directory containing "${FACTORIO_SAVE}"         | Specifies the directory where Factorio save files are stored. |

When using `MAPSHOT_SAVE_MODE="latest` the generated Mapshots will likely be named like: `_autosave1`,`_autosave2`,`_autosave3` etc.  
Combining `MAPSHOT_SAVE_MODE="latest` with `MAPSHOT_SAVE_NAME="mysave"` the generated Mapshots will be named `mysave`.

## Docker Compose

There are two services in the docker-compose.yml file: mapshot-renderer and mapshot-server. Both services use the same image.

```yaml
version: '3.8'

services:
  mapshot-renderer:
    image: martydingo/mapshot:latest
    environment:
      FACTORIO_USERNAME: ""
      FACTORIO_TOKEN: "
      FACTORIO_SAVE: "/opt/factorio/saves/_autosave1.zip"
      MAPSHOT_AREA: "_all_"
      MAPSHOT_JPEG_QUALITY: "95"
      MAPSHOT_MINIMUM_JPEG_QUALITY: "95"
      MAPSHOT_MINIMUM_TILES: "64"
      MAPSHOT_MODE: "render"
      MAPSHOT_SURFACES_TO_RENDER: "_all_"
      MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT: "9"
      MAPSHOT_INTERVAL: "600"
    volumes:
      - factorio-data:/opt/factorio:ro
      - mapshot-data:/opt/mapshot

  mapshot-server:
    image: martydingo/mapshot:latest
    environment:
      MAPSHOT_MODE: "serve"
      MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT: "9"
    ports:
      - "8080:8080"
    volumes:
      - mapshot-data:/opt/mapshot

volumes:
  factorio-data:
    external: true  # If the data is managed by an external volume like in Kubernetes PVCs
  mapshot-data:
    external: true  # If the data is managed by an external volume like in Kubernetes PVCs

```

## Kubernetes

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mapshot
  labels:
    app: mapshot
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mapshot
  template:
    metadata:
      labels:
        app: mapshot
    spec:
      containers:
        - name: mapshot-renderer
          image: martydingo/mapshot:latest
          imagePullPolicy: Always
          env:
            - name: FACTORIO_USERNAME
              valueFrom:
                secretKeyRef:
                  name: factorio-credentials
                  key: username
            - name: FACTORIO_TOKEN
              valueFrom:
                secretKeyRef:
                  name: factorio-credentials
                  key: token
            - name: FACTORIO_SAVE
              value: "/opt/factorio/saves/_autosave1.zip"
            - name: MAPSHOT_AREA
              value: "_all_"
            - name: MAPSHOT_JPEG_QUALITY
              value: "95"
            - name: MAPSHOT_MINIMUM_JPEG_QUALITY
              value: "95"
            - name: MAPSHOT_MINIMUM_TILES
              value: "64"
            - name: MAPSHOT_MODE
              value: "render"
            - name: MAPSHOT_SURFACES_TO_RENDER
              value: "_all_"
            - name: MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT
              value: "9"
            - name: MAPSHOT_INTERVAL
              value: "600"
          volumeMounts:
            - mountPath: /opt/factorio
              name: factorio-mapshot
              readOnly: true
            - mountPath: /opt/mapshot
              name: mapshot-mapshot
        - name: mapshot-server
          image: martydingo/mapshot:latest
          imagePullPolicy: Always
          env:
            - name: MAPSHOT_MODE
              value: "serve"
            - name: MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT
              value: "9"
          ports:
            - containerPort: 8080
              protocol: TCP
              name: http
          volumeMounts:
            - mountPath: /opt/mapshot
              name: mapshot-mapshot
      volumes:
        - name: factorio-mapshot
          persistentVolumeClaim:
            claimName: factorio-mapshot
        - name: mapshot-mapshot
          persistentVolumeClaim:
            claimName: mapshot-mapshot

```

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: factorio-credentials
data:
  username: <base64-encoded-username>
  token: <base64-encoded-token>
```

### Storage

```yaml
#####
### mapshot
#####

####
## Persistent Volume YAML
####
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: factorio-mapshot
spec:
  capacity:
    storage: 4Gi  # Adjust this according to your storage requirements
  accessModes:
    - ReadWriteMany
  nfs:
    path: /path/to/factorio/data  # Adjust the NFS path as necessary
    server: 10.0.254.1  # Replace with your NFS server's IP or hostname

---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mapshot-mapshot
spec:
  capacity:
    storage: 2Gi  # Adjust this according to your storage requirements
  accessModes:
    - ReadWriteOnce
  nfs:
    path: /path/to/mapshot/data  # Adjust the NFS path as necessary
    server: 10.0.254.1  # Replace with your NFS server's IP or hostname

####
## Persistent Volume Claim YAML
####
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: factorio-mapshot
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 4Gi  # This should match the PV capacity
  volumeName: factorio-mapshot
  storageClassName: ""  # Set to "" to avoid a dynamic provisioner, or specify a class if needed

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mapshot-mapshot
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi  # This should match the PV capacity
  volumeName: mapshot-mapshot
  storageClassName: ""  # Set to "" to avoid a dynamic provisioner, or specify a class if needed

```

#### Persistent Volumes (PV):

The factorio-mapshot volume is configured to store Factorio game data (e.g., save files).
The mapshot-mapshot volume is set for storing mapshot-related data.
Replace the path and server with the appropriate values for your NFS setup.

#### Persistent Volume Claims (PVC):

PVCs are defined for both factorio-mapshot and mapshot-mapshot. The claims reference the corresponding PVs and specify storage requirements matching the PVs' capacities. The `storageClassName` is left empty (""), which means it will not use a dynamic provisioner. You can set a specific storage class if required.

##### Storage Capacity

The storage values (4Gi for the Factorio data and 2Gi for the mapshot data) are just examples and can be adjusted based on your actual data requirements.

#### Volume Names

The PVCs reference the PVs by name (factorio-mapshot and mapshot-mapshot). Ensure that the name of the PVs and PVCs match in your setup.

Ensure that the NFS server is properly configured and accessible by the Kubernetes nodes.

Make adjustments to the storage values based on your actual needs for Factorio save data and mapshot data.

You may need to modify the accessModes and storageClassName if you're using a different storage backend or dynamic provisioning system (e.g., cloud-based persistent storage).
