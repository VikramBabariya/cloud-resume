graph LR
%% Definitions
User((User/Browser))
R53[Route 53 <br> DNS]
CF[CloudFront <br> CDN]
S3[S3 Bucket <br> Static Website]
ACM[ACM <br> SSL Certificate]

    APIG[API Gateway]

    %% Flow A: Counter
    LambdaCount[Lambda Function <br> Visitor Counter]
    DDB[(DynamoDB <br> Database)]

    %% Flow B: Validator
    LambdaValid[Lambda Function <br> Credential Validator]
    SSM[SSM Parameter Store <br> SecureString]
    ExtAPI((External <br> Credential API))

    CW[CloudWatch <br> Logs & Metrics]
    XRay[X-Ray <br> Tracing]

    GH[GitHub Actions <br> CI/CD Pipeline]

    %% Infrastructure Flow
    User -- HTTPS Request --> R53
    R53 -- Resolves --> CF
    CF -- GET (Frontend) --> S3
    CF -. Uses .- ACM

    %% Frontend to Backend
    S3 -- JS Fetch --> APIG

    %% Backend Flow A (Counter)
    APIG -- Route: /counter --> LambdaCount
    LambdaCount -- Update/Read --> DDB

    %% Backend Flow B (Credential Validation)
    APIG -- Route: /verify --> LambdaValid
    LambdaValid -- ssm:GetParameter --> SSM
    LambdaValid -- HTTPS TLS --> ExtAPI

    %% Observability
    APIG -. Traces .-> XRay
    LambdaCount -. Logs/Metrics .-> CW
    LambdaCount -. Traces .-> XRay
    LambdaValid -. Logs/Metrics .-> CW
    LambdaValid -. Traces .-> XRay

    %% CI/CD
    GH -- Syncs Assets --> S3

    %% Styles
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:white;
    classDef db fill:#3F8624,stroke:#232F3E,stroke-width:2px,color:white;
    classDef obs fill:#E7157B,stroke:#232F3E,stroke-width:2px,color:white;
    classDef sec fill:#DD344C,stroke:#232F3E,stroke-width:2px,color:white;
    classDef ext fill:#8C4FFF,stroke:#232F3E,stroke-width:2px,color:white;

    class LambdaCount,LambdaValid,APIG,S3,CF,R53,ACM aws;
    class DDB db;
    class CW,XRay obs;
    class SSM sec;
    class ExtAPI ext;
