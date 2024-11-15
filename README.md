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

| Environment Variable                  | Default Value                                       | Description                                                                                                                                          |
| ------------------------------------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| MAPSHOT_ROOT_DIRECTORY                | "/mapshot"                                          | Defines the root directory where Factorio files and related data are located. Defaults to /mapshot if not set.                                       |
| FACTORIO_USERNAME                     | N/A                                                 | The username required to authenticate with Factorio's website to download Factorio game files.                                                       |
| FACTORIO_TOKEN                        | N/A                                                 | The authentication token associated with the user, used in conjunction with FACTORIO_USERNAME to authenticate Factorio downloads.                    |
| MAPSHOT_FACTORIO_DATA_DIRECTORY       | "$MAPSHOT_ROOT_DIRECTORY/factorio"                  | Specifies the directory where Factorio data (saves, mods, etc.) is stored. Defaults to $MAPSHOT_ROOT_DIRECTORY/factorio if not set.                  |
| MAPSHOT_FACTORIO_BINARY_PATH          | "$MAPSHOT_ROOT_DIRECTORY/factorio/bin/x64/factorio" | Defines the path to the Factorio binary (executable). Defaults to $MAPSHOT_ROOT_DIRECTORY/factorio/bin/x64/factorio if not set.                      |
| MAPSHOT_MODE                          | N/A                                                 | Determines the script's operation mode: "render" for rendering maps or "serve" for starting a Factorio server to serve the map.                      |
| MAPSHOT_WORKING_DIRECTORY             | "$MAPSHOT_ROOT_DIRECTORY/factorio"                  | Defines the working directory for temporary files during Factorio operations. Defaults to $MAPSHOT_ROOT_DIRECTORY/factorio if not set.               |
| MAPSHOT_AREA                          | "all"                                               | Specifies which area of the map to render. Defaults to "all", meaning the entire map is rendered.                                                    |
| MAPSHOT_MINIMUM_TILES                 | 64                                                  | Defines the minimum number of tiles used for map rendering. Controls the map's resolution.                                                           |
| MAPSHOT_MAXIMUM_TILES                 | 0                                                   | Defines the maximum number of tiles used for rendering. A value of 0 means no limit.                                                                 |
| MAPSHOT_JPEG_QUALITY                  | 90                                                  | Controls the quality of the rendered map in JPEG format. The value is a percentage, where a higher value results in better quality but larger files. |
| MAPSHOT_MINIMUM_JPEG_QUALITY          | 90                                                  | Specifies the minimum JPEG quality for rendered images. The script will adjust the image quality if it falls below this threshold.                   |
| MAPSHOT_SURFACES_TO_RENDER            | "all_"                                              | Determines which surfaces of the Factorio map to render. Defaults to all surfaces (*all*). Can be set to specific surfaces (e.g., "nauvis").         |
| MAPSHOT_VERBOSE_FACTORIO_LOGGING      | Not set (optional)                                  | Enables verbose logging for Factorio during rendering or serving. If set, the script will include the --factorio_verbose flag.                       |
| MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT | 9                                                   | Controls the verbosity of the mapshot tool's logging. The higher the number, the more detailed the logs. Defaults to 9, the most detailed log level. |
| MAPSHOT_INTERVAL                      | 600                                                 | Defines the interval (in seconds) between map renders when the script is running in render mode. A higher value means fewer renders.                 |
| FACTORIO_SAVE                         | N/A                                                 | Specifies the path to the Factorio save file that will be used for map rendering. This is the save file the mapshot tool will render into an image.  |

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
      - mapshot-data:/mapshot
    restart: on-failure # Restart on failure (non-zero exit code)

  mapshot-server:
    image: martydingo/mapshot:latest
    environment:
      MAPSHOT_MODE: "serve"
      MAPSHOT_VERBOSE_MAPSHOT_LOG_LEVEL_INT: "9"
    ports:
      - "8080:8080"
    volumes:
      - mapshot-data:/mapshot

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
            - mountPath: /mapshot
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
            - mountPath: /mapshot
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
